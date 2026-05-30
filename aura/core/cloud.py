import logging
import os
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / "config" / ".env")

log = logging.getLogger(__name__)

_SUPABASE_URL = os.getenv("SUPABASE_URL", "")
_SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
_INSTALLATION_ID = os.getenv("INSTALLATION_ID", "")

_client = None


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


def is_connected() -> bool:
    """Return True if a Supabase client has been successfully initialised."""
    return _get_client() is not None


def sync_vehicles() -> list[dict]:
    """Return active vehicles for this installation from Supabase, or [] if unreachable."""
    client = _get_client()
    if client is None:
        return []
    try:
        response = (
            client.table("vehicles")
            .select("*")
            .eq("installation_id", _INSTALLATION_ID)
            .eq("is_active", True)
            .execute()
        )
        return response.data or []
    except Exception as exc:
        log.warning("sync_vehicles failed: %s", exc)
        return []


def sync_settings() -> dict:
    """Return settings for this installation as a key:value dict, or {} if unreachable."""
    client = _get_client()
    if client is None:
        return {}
    try:
        response = (
            client.table("settings")
            .select("key, value")
            .eq("installation_id", _INSTALLATION_ID)
            .execute()
        )
        return {row["key"]: row["value"] for row in (response.data or [])}
    except Exception as exc:
        log.warning("sync_settings failed: %s", exc)
        return {}


def log_recognition(
    detected_make: str,
    detected_model: str,
    confidence: float,
    method: str,
    matched_vehicle_id: int | None = None,
) -> dict | None:
    """Insert a recognition event. Returns the inserted row or None on failure."""
    client = _get_client()
    if client is None:
        return None
    payload = {
        "installation_id": _INSTALLATION_ID,
        "detected_make": detected_make,
        "detected_model": detected_model,
        "confidence": confidence,
        "method": method,
        "matched_vehicle_id": matched_vehicle_id,
    }
    try:
        response = client.table("recognition_events").insert(payload).execute()
        return response.data[0] if response.data else None
    except Exception as exc:
        log.warning("log_recognition failed: %s", exc)
        return None


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
