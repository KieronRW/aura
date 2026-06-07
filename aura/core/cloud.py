import logging
import os
import socket
from datetime import datetime, timezone
from pathlib import Path

import psutil
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / "config" / ".env")

log = logging.getLogger(__name__)

_SUPABASE_URL = os.getenv("SUPABASE_URL", "")
_SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
_INSTALLATION_ID = os.getenv("INSTALLATION_ID", "")

_client = None
_installation_uuid: str | None = None  # resolved once from installation_key, then cached


def _get_client():
    global _client
    if _client is not None:
        return _client
    if not _SUPABASE_URL or not _SUPABASE_KEY:
        log.debug("Supabase credentials not configured — running offline")
        return None
    try:
        from supabase import create_client
        _client = create_client(_SUPABASE_URL, _SUPABASE_KEY)
        return _client
    except Exception as exc:
        log.warning("Supabase client init failed: %s", exc)
        return None


def _get_installation_uuid() -> str | None:
    """Resolve and cache the installations.id UUID for the configured installation_key."""
    global _installation_uuid
    if _installation_uuid is not None:
        return _installation_uuid
    client = _get_client()
    if client is None:
        return None
    try:
        response = (
            client.table("installations")
            .select("id")
            .eq("installation_key", _INSTALLATION_ID)
            .execute()
        )
        if response.data:
            _installation_uuid = response.data[0]["id"]
            log.debug("Resolved installation UUID for key %r: %s", _INSTALLATION_ID, _installation_uuid)
            return _installation_uuid
        log.warning("No installation found for installation_key=%r", _INSTALLATION_ID)
        return None
    except Exception as exc:
        log.warning("Installation UUID lookup failed: %s", exc)
        return None


def is_connected() -> bool:
    """Return True if a Supabase client has been successfully initialised."""
    return _get_client() is not None


def sync_vehicles() -> list[dict]:
    """Return active vehicles for this installation from Supabase, or [] if unreachable.

    Joins vehicles → profiles → installations and filters by
    installations.installation_key = INSTALLATION_ID.
    Each vehicle dict gains a 'reference_fingerprints' key: a list of
    fingerprint_data JSON strings from vehicle_reference_images.
    """
    client = _get_client()
    if client is None:
        return []
    try:
        response = (
            client.table("vehicles")
            .select("*, profiles!inner(installations!inner(installation_key))")
            .eq("is_active", True)
            .filter("profiles.installations.installation_key", "eq", _INSTALLATION_ID)
            .execute()
        )
        vehicles = response.data or []
        for v in vehicles:
            v.pop("profiles", None)

        if vehicles:
            vehicle_ids = [v["id"] for v in vehicles]
            ref_resp = (
                client.table("vehicle_reference_images")
                .select("vehicle_id, fingerprint_data")
                .in_("vehicle_id", vehicle_ids)
                .not_.is_("fingerprint_data", "null")
                .execute()
            )
            ref_map: dict[int, list[str]] = {}
            for row in (ref_resp.data or []):
                ref_map.setdefault(row["vehicle_id"], []).append(row["fingerprint_data"])
            for v in vehicles:
                v["reference_fingerprints"] = ref_map.get(v["id"], [])

        return vehicles
    except Exception as exc:
        log.warning("sync_vehicles failed: %s", exc)
        return []


def sync_settings() -> dict:
    """Return device_settings for this installation as a key:value dict, or {} if unreachable."""
    client = _get_client()
    if client is None:
        return {}
    try:
        response = (
            client.table("device_settings")
            .select("setting_key, setting_value, installations!inner(installation_key)")
            .filter("installations.installation_key", "eq", _INSTALLATION_ID)
            .execute()
        )
        return {
            row["setting_key"]: row["setting_value"]
            for row in (response.data or [])
        }
    except Exception as exc:
        log.warning("sync_settings failed: %s", exc)
        return {}


def upload_recognition_image(frame, event_id: str) -> str | None:
    """Encode frame as JPEG and upload to Supabase Storage. Returns storage path or None."""
    client = _get_client()
    if client is None:
        return None
    try:
        import cv2
        ok, buf = cv2.imencode(".jpg", frame)
        if not ok:
            log.warning("upload_recognition_image: cv2.imencode failed")
            return None
        path = f"{_INSTALLATION_ID}/{event_id}.jpg"
        client.storage.from_("recognition-images").upload(
            path,
            buf.tobytes(),
            {"content-type": "image/jpeg"},
        )
        return path
    except Exception as exc:
        log.warning("upload_recognition_image failed: %s", exc)
        return None


def log_recognition(
    detected_make: str,
    detected_model: str,
    confidence: float,
    method: str,
    matched_vehicle_id: int | None = None,
    image_frame=None,
) -> dict | None:
    """Insert a recognition event. Returns the inserted row or None on failure."""
    client = _get_client()
    if client is None:
        return None
    uuid = _get_installation_uuid()
    if uuid is None:
        log.warning("log_recognition: installation UUID unavailable — event not recorded")
        return None
    payload = {
        "installation_id": uuid,
        "arrived_at": datetime.now(timezone.utc).isoformat(),
        "detected_make": detected_make,
        "detected_model": detected_model,
        "confidence": confidence,
        "method": method,
        "vehicle_id": matched_vehicle_id,
    }
    try:
        response = client.table("recognition_events").insert(payload).execute()
        row = response.data[0] if response.data else None
    except Exception as exc:
        log.warning("log_recognition failed: %s", exc)
        return None

    if row and image_frame is not None:
        image_path = upload_recognition_image(image_frame, str(row["id"]))
        if image_path:
            try:
                client.table("recognition_events").update({"image_path": image_path}).eq("id", row["id"]).execute()
                row["image_path"] = image_path
            except Exception as exc:
                log.warning("log_recognition: image_path update failed for event %s: %s", row["id"], exc)

    return row


def save_autolearn_image(vehicle_id: int, frame) -> bool:
    """
    Upload frame to reference-images storage and insert a vehicle_reference_images row.
    Increments vehicles.reference_image_count. Returns True on success.
    """
    client = _get_client()
    if client is None:
        return False
    try:
        import cv2
        ok, buf = cv2.imencode(".jpg", frame)
        if not ok:
            log.warning("save_autolearn_image: imencode failed")
            return False

        timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        path = f"{vehicle_id}/auto_{timestamp}.jpg"

        client.storage.from_("reference-images").upload(
            path, buf.tobytes(), {"content-type": "image/jpeg"}
        )
        client.table("vehicle_reference_images").insert({
            "vehicle_id": vehicle_id,
            "storage_path": path,
            "is_active": True,
            "angle": "auto",
        }).execute()

        # Increment reference_image_count (read-then-write; auto-learn rate-limits to 1/hr)
        resp = (
            client.table("vehicles")
            .select("reference_image_count")
            .eq("id", vehicle_id)
            .execute()
        )
        current = (resp.data[0].get("reference_image_count") or 0) if resp.data else 0
        client.table("vehicles").update(
            {"reference_image_count": current + 1}
        ).eq("id", vehicle_id).execute()

        return True
    except Exception as exc:
        log.warning("save_autolearn_image failed for vehicle %s: %s", vehicle_id, exc)
        return False


def update_departure(event_id: int) -> bool:
    """Set departed_at to now() on a recognition event. Returns True on success."""
    client = _get_client()
    if client is None:
        return False
    departed_at = datetime.now(timezone.utc).isoformat()
    try:
        client.table("recognition_events").update({"departed_at": departed_at}).eq("id", event_id).execute()
        return True
    except Exception as exc:
        log.warning("update_departure failed for event %s: %s", event_id, exc)
        return False


def push_heartbeat(
    camera_ok: bool,
    display_clients: int,
    current_state: str,
    software_version: str,
) -> None:
    """Upsert a heartbeat row into device_status. Fails silently if Supabase is unreachable."""
    client = _get_client()
    if client is None:
        return
    uuid = _get_installation_uuid()
    if uuid is None:
        return

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
    except OSError:
        local_ip = None

    try:
        uptime_seconds = int(float(Path("/proc/uptime").read_text().split()[0]))
    except OSError:
        uptime_seconds = None

    payload = {
        "installation_id":  uuid,
        "is_online":        True,
        "last_seen_at":     datetime.now(timezone.utc).isoformat(),
        "local_ip":         local_ip,
        "uptime_seconds":   uptime_seconds,
        "cpu_percent":      psutil.cpu_percent(interval=None),
        "memory_percent":   psutil.virtual_memory().percent,
        "disk_percent":     psutil.disk_usage("/").percent,
        "software_version": software_version,
        "camera_ok":        camera_ok,
        "display_clients":  display_clients,
        "current_state":    current_state,
    }

    try:
        client.table("device_status").upsert(payload, on_conflict="installation_id").execute()
        log.debug("Heartbeat sent")
    except Exception as exc:
        log.warning("push_heartbeat failed: %s", exc)
