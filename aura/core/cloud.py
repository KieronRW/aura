import asyncio
import logging
import os
import socket
import subprocess
import threading
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


def get_installation_uuid() -> str | None:
    """Return the resolved installation UUID for this device, or None if unavailable."""
    return _get_installation_uuid()


def subscribe_visitor_updates(installation_uuid: str, on_change) -> None:
    """Start a background Realtime subscription for visitors table UPDATE events.

    Calls on_change() whenever any visitor row for this installation is updated.
    Uses acreate_client + a dedicated asyncio event loop in a daemon thread —
    the same pattern used by ReferenceImageEnroller for INSERT subscriptions.
    Falls back silently if Supabase is unavailable; the 5-minute periodic sync
    in main.py remains the safety net.
    """
    if not _SUPABASE_URL or not _SUPABASE_KEY:
        log.warning("subscribe_visitor_updates: Supabase not configured — skipping")
        return

    async def _realtime_main() -> None:
        from supabase import acreate_client
        rt_client = await acreate_client(_SUPABASE_URL, _SUPABASE_KEY)

        def _callback(payload, *_) -> None:
            event = (payload or {}).get("eventType", "?")
            log.debug("Realtime: visitors %s received — %s", event, payload)
            try:
                on_change()
            except Exception as exc:
                log.warning("Realtime visitor on_change error: %s", exc)

        channel = rt_client.channel(f"aura-visitors-{installation_uuid}")
        channel.on_postgres_changes(
            event="*",
            schema="public",
            table="visitors",
            filter=f"installation_id=eq.{installation_uuid}",
            callback=_callback,
        )
        await channel.subscribe()
        log.info("Realtime: subscribed to visitors INSERT/UPDATE/DELETE (uuid=%s)", installation_uuid)

        while True:
            await asyncio.sleep(1.0)

    def _run() -> None:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            loop.run_until_complete(_realtime_main())
        except Exception as exc:
            log.warning("Realtime visitor subscription failed: %s", exc)
        finally:
            loop.close()

    threading.Thread(target=_run, daemon=True, name="realtime-visitors").start()


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


def get_property_location(installation_uuid: str) -> tuple[float | None, float | None, str | None]:
    """Return (latitude, longitude, user_id) for the property linked to this installation.

    Returns (None, None, None) if unavailable. Caller should cache; this does not cache internally.
    Uses a left join (not !inner) so the installation row is returned even when property_id is null.
    """
    client = _get_client()
    if client is None:
        return None, None, None
    try:
        response = (
            client.table("installations")
            .select("properties(latitude, longitude, user_id)")
            .eq("id", installation_uuid)
            .limit(1)
            .execute()
        )
        if not response.data:
            log.warning(
                "get_property_location: installation %s not found in database",
                installation_uuid,
            )
            return None, None, None
        prop = (response.data[0].get("properties") or {})
        if not prop:
            log.warning(
                "get_property_location: installation %s has no linked property"
                " — set installations.property_id in Supabase",
                installation_uuid,
            )
            return None, None, None
        lat = prop.get("latitude")
        lon = prop.get("longitude")
        user_id = prop.get("user_id")
        log.info(
            "get_property_location: resolved lat=%s lon=%s user_id=%s for installation %s",
            lat, lon, user_id, installation_uuid,
        )
        return (
            float(lat) if lat is not None else None,
            float(lon) if lon is not None else None,
            str(user_id) if user_id is not None else None,
        )
    except Exception as exc:
        log.warning("get_property_location failed: %s", exc)
        return None, None, None


def get_user_preferences(user_id: str) -> dict:
    """Return app_preferences for user_id as {"units": ..., "time_format": ...}.

    Defaults to metric / 24h if row not found. Never raises.
    """
    client = _get_client()
    if client is None:
        return {"units": "metric", "time_format": "24h"}
    try:
        response = (
            client.table("app_preferences")
            .select("units, time_format")
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
        prefs = response.data[0] if response.data else {}
        return {
            "units": prefs.get("units") or "metric",
            "time_format": prefs.get("time_format") or "24h",
        }
    except Exception as exc:
        log.warning("get_user_preferences failed: %s", exc)
        return {"units": "metric", "time_format": "24h"}


def get_expected_visitors(installation_id: str | None = None) -> list[dict]:
    """Return active expected visitors for this installation, or [] if unreachable.

    Filters visitors where is_active=true and (expected_until is null OR expected_until > now).
    Pass installation_id explicitly or leave None to use the module-level INSTALLATION_ID.
    """
    client = _get_client()
    if client is None:
        return []
    uuid = installation_id or _get_installation_uuid()
    if uuid is None:
        return []
    try:
        now = datetime.now(timezone.utc).isoformat()
        response = (
            client.table("visitors")
            .select("*")
            .eq("installation_id", uuid)
            .eq("is_active", True)
            .or_(f"expected_until.is.null,expected_until.gt.{now}")
            .execute()
        )
        return response.data or []
    except Exception as exc:
        log.warning("get_expected_visitors failed: %s", exc)
        return []


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
    *,
    visitor_id=None,
    needs_review: bool = False,
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
        "visitor_id": visitor_id,
        "needs_review": needs_review,
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

    if row:
        trigger_automation_webhooks(row)

    return row


def _post_webhook(url: str, payload: dict, headers: dict, rule_name: str | None) -> None:
    """POST JSON to url. Logs errors; never raises."""
    import json
    body = json.dumps(payload).encode()
    try:
        try:
            import requests as _requests
            resp = _requests.post(url, data=body, headers=headers, timeout=5)
            log.info("Webhook fired for rule %r → %s (HTTP %s)", rule_name, url, resp.status_code)
        except ImportError:
            import urllib.request
            req = urllib.request.Request(url, data=body, headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=5) as resp:
                log.info("Webhook fired for rule %r → %s (HTTP %s)", rule_name, url, resp.status)
    except Exception as exc:
        log.warning("Webhook failed for rule %r (%s): %s", rule_name, url, exc)


def trigger_automation_webhooks(row: dict) -> None:
    """Fire matching webhook automation rules in a background thread. Never blocks."""

    def _run() -> None:
        log.info(
            "trigger_automation_webhooks: starting (installation_id=%s vehicle_id=%s visitor_id=%s)",
            row.get("installation_id"), row.get("vehicle_id"), row.get("visitor_id"),
        )
        client = _get_client()
        if client is None:
            log.info("trigger_automation_webhooks: no Supabase client — aborting")
            return
        installation_id = row.get("installation_id")
        if not installation_id:
            log.info("trigger_automation_webhooks: no installation_id in row — aborting")
            return

        try:
            # Fetch all active webhook rules; filter installation_ids in Python to avoid
            # PostgREST array-literal URL-encoding issues with .or_() + cs operator.
            response = (
                client.table("automation_rules")
                .select("*")
                .eq("is_active", True)
                .eq("action_type", "webhook")
                .execute()
            )
            all_rules = response.data or []
            log.info("trigger_automation_webhooks: fetched %d active webhook rules total", len(all_rules))
        except Exception as exc:
            log.warning("trigger_automation_webhooks: rule query failed: %s", exc)
            return

        # installation_ids=null means global (any installation); otherwise must contain ours
        rules = [
            r for r in all_rules
            if r.get("installation_ids") is None
            or installation_id in (r.get("installation_ids") or [])
        ]
        log.info(
            "trigger_automation_webhooks: %d rules apply to installation %s: %s",
            len(rules), installation_id, [r.get("name") for r in rules],
        )

        vehicle_id = row.get("vehicle_id")
        visitor_id = row.get("visitor_id")
        _profile_cache: dict = {}

        def _profile_id_for(vid) -> str | None:
            if vid in _profile_cache:
                return _profile_cache[vid]
            try:
                resp = client.table("vehicles").select("profile_id").eq("id", vid).execute()
                pid = resp.data[0]["profile_id"] if resp.data else None
            except Exception as exc:
                log.warning("trigger_automation_webhooks: vehicle lookup failed: %s", exc)
                pid = None
            _profile_cache[vid] = pid
            return pid

        now_ts = datetime.now(timezone.utc).isoformat()

        for rule in rules:
            trigger = rule.get("trigger_type")
            rule_name = rule.get("name")

            if trigger == "profile_detected":
                if vehicle_id is None:
                    log.info("Rule %r skipped: profile_detected but vehicle_id is None", rule_name)
                    continue
                found_profile = _profile_id_for(vehicle_id)
                if found_profile != rule.get("profile_id"):
                    log.info(
                        "Rule %r skipped: profile mismatch (vehicle=%s rule=%s)",
                        rule_name, found_profile, rule.get("profile_id"),
                    )
                    continue
            elif trigger == "any_resident_detected":
                if vehicle_id is None:
                    log.info("Rule %r skipped: any_resident_detected but vehicle_id is None", rule_name)
                    continue
            elif trigger == "visitor_arrival":
                if visitor_id is None:
                    log.info("Rule %r skipped: visitor_arrival but visitor_id is None", rule_name)
                    continue
            elif trigger == "unknown_vehicle":
                if vehicle_id is not None or visitor_id is not None:
                    log.info(
                        "Rule %r skipped: unknown_vehicle but vehicle_id=%s visitor_id=%s",
                        rule_name, vehicle_id, visitor_id,
                    )
                    continue
            else:
                log.info("Rule %r skipped: trigger %r not handled here", rule_name, trigger)
                continue

            config = rule.get("action_config") or {}
            url = config.get("url", "")
            if not url:
                log.warning("trigger_automation_webhooks: rule %r has no URL — skipping", rule_name)
                continue

            headers = {"Content-Type": "application/json"}
            extra = config.get("headers") or {}
            if isinstance(extra, dict):
                headers.update(extra)

            payload = {
                "event": trigger,
                "rule_name": rule_name,
                "installation_id": installation_id,
                "detected_make": row.get("detected_make"),
                "detected_model": row.get("detected_model"),
                "vehicle_id": vehicle_id,
                "visitor_id": visitor_id,
                "timestamp": now_ts,
            }

            log.info("trigger_automation_webhooks: firing rule %r → %s", rule_name, url)
            _post_webhook(url, payload, headers, rule_name)

    threading.Thread(target=_run, daemon=True, name="automations-webhooks").start()


def log_unknown_vehicle(
    detected_make: str | None,
    detected_model: str | None,
    confidence: float,
    image_frame=None,
) -> dict | None:
    """Insert a row into unknown_vehicles. Returns the inserted row or None on failure."""
    client = _get_client()
    if client is None:
        return None
    uuid = _get_installation_uuid()
    if uuid is None:
        return None
    payload = {
        "installation_id": uuid,
        "detected_make": detected_make,
        "detected_model": detected_model,
        "confidence": confidence,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    try:
        response = client.table("unknown_vehicles").insert(payload).execute()
        row = response.data[0] if response.data else None
    except Exception as exc:
        log.warning("log_unknown_vehicle failed: %s", exc)
        return None

    if row and image_frame is not None:
        image_path = upload_recognition_image(image_frame, str(row["id"]))
        if image_path:
            try:
                client.table("unknown_vehicles").update({"image_path": image_path}).eq("id", row["id"]).execute()
                row["image_path"] = image_path
            except Exception as exc:
                log.warning("log_unknown_vehicle: image_path update failed for id=%s: %s", row["id"], exc)

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


def _get_cpu_temp() -> float | None:
    try:
        result = subprocess.run(
            ["vcgencmd", "measure_temp"],
            capture_output=True, text=True, timeout=2,
        )
        temp_str = result.stdout.strip().replace("temp=", "").replace("'C", "")
        return float(temp_str)
    except Exception:
        return None


def get_cpu_temp() -> float | None:
    """Return the Pi CPU temperature in °C, or None if unavailable."""
    return _get_cpu_temp()


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
        "cpu_temp_c":       _get_cpu_temp(),
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


def send_push_notification(title: str, body: str) -> bool:
    """Invoke the send-push Supabase edge function. Fails silently if unavailable."""
    client = _get_client()
    if client is None:
        return False
    uuid = _get_installation_uuid()
    if uuid is None:
        log.debug("send_push_notification: no installation UUID — skipping")
        return False
    try:
        client.functions.invoke(
            "send-push",
            invoke_options={"body": {
                "installation_id": uuid,
                "title": title,
                "body": body,
            }},
        )
        log.info("Push notification sent: %s", title)
        return True
    except Exception as exc:
        log.warning("send_push_notification failed: %s", exc)
        return False
