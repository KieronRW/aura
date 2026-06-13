import logging
import os
import time as _time
from pathlib import Path
from typing import Any

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / "config" / ".env")

log = logging.getLogger(__name__)

_SUPABASE_URL = os.getenv("SUPABASE_URL", "")
_SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
_INSTALLATION_ID = os.getenv("INSTALLATION_ID", "")

DEFAULTS: dict[str, Any] = {
    "vision_confidence_gate": 0.75,   # min Vision confidence to trust result
    "auto_learn_min": 0.60,           # auto-learn fingerprint score range min
    "auto_learn_max": 0.72,           # auto-learn fingerprint score range max
    "offline_fp_threshold": 0.60,     # fingerprint threshold when offline
}

_client = None
_installation_uuid: str | None = None

# Simple time-based cache so recognize() doesn't hit Supabase on every call
_settings_cache: dict | None = None
_settings_cache_at: float = 0.0
_CACHE_TTL = 60.0  # seconds


def _get_client():
    global _client
    if _client is not None:
        return _client
    if not _SUPABASE_URL or not _SUPABASE_KEY:
        return None
    try:
        from supabase import create_client
        _client = create_client(_SUPABASE_URL, _SUPABASE_KEY)
        return _client
    except Exception as exc:
        log.warning("recognition_settings: Supabase init failed: %s", exc)
        return None


def _get_installation_uuid() -> str | None:
    global _installation_uuid
    if _installation_uuid is not None:
        return _installation_uuid
    client = _get_client()
    if client is None:
        return None
    try:
        resp = (
            client.table("installations")
            .select("id")
            .eq("installation_key", _INSTALLATION_ID)
            .execute()
        )
        if resp.data:
            _installation_uuid = resp.data[0]["id"]
            return _installation_uuid
        log.warning("recognition_settings: no installation for key %r", _INSTALLATION_ID)
    except Exception as exc:
        log.warning("recognition_settings: UUID lookup failed: %s", exc)
    return None


def get_settings() -> dict[str, Any]:
    """Return recognition settings merged with defaults, loading from Supabase device_settings."""
    settings: dict[str, Any] = dict(DEFAULTS)
    client = _get_client()
    if client is None:
        return settings
    try:
        resp = (
            client.table("device_settings")
            .select("setting_key, setting_value, installations!inner(installation_key)")
            .filter("installations.installation_key", "eq", _INSTALLATION_ID)
            .execute()
        )
        for row in (resp.data or []):
            key = row["setting_key"]
            if key not in DEFAULTS:
                continue
            val: Any = row["setting_value"]
            default = DEFAULTS[key]
            try:
                if isinstance(default, bool):
                    val = str(val).lower() in ("true", "1", "yes")
                elif isinstance(default, float):
                    val = float(val)
                elif isinstance(default, int):
                    val = int(float(val))
            except (ValueError, TypeError):
                continue
            settings[key] = val
    except Exception as exc:
        log.warning("recognition_settings: get_settings failed: %s", exc)
    return settings


def get_settings_cached() -> dict[str, Any]:
    """Return settings from cache, refreshing from Supabase at most every 60 seconds."""
    global _settings_cache, _settings_cache_at
    now = _time.monotonic()
    if _settings_cache is None or now - _settings_cache_at >= _CACHE_TTL:
        _settings_cache = get_settings()
        _settings_cache_at = now
    return _settings_cache


def save_settings(params: dict[str, Any]) -> bool:
    """Persist recognition settings to device_settings. Returns True on success."""
    global _settings_cache  # invalidate cache on save
    client = _get_client()
    if client is None:
        return False
    uuid = _get_installation_uuid()
    if uuid is None:
        return False
    try:
        for key, value in params.items():
            if key not in DEFAULTS:
                continue
            client.table("device_settings").upsert(
                {
                    "installation_id": uuid,
                    "setting_key": key,
                    "setting_value": str(value),
                },
                on_conflict="installation_id,setting_key",
            ).execute()
        _settings_cache = None  # force refresh on next get_settings_cached() call
        return True
    except Exception as exc:
        log.warning("recognition_settings: save_settings failed: %s", exc)
        return False
# OTA test Sat 13 Jun 2026 21:31:25 SAST
