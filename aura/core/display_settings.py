import logging
import os
import subprocess
from pathlib import Path
from typing import Any

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / "config" / ".env")

log = logging.getLogger(__name__)

_SUPABASE_URL = os.getenv("SUPABASE_URL", "")
_SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
_INSTALLATION_ID = os.getenv("INSTALLATION_ID", "")

DEFAULTS: dict[str, Any] = {
    "display_rotation": 90,  # 0, 90, 180, 270 — matches autostart wlr-randr default
    "show_time": False,
    "show_weather": False,
    "status_bar_scale": 100,  # percentage, 50–200; 100 = default size
    "auto_update": True,      # units stay current by default; updated between 02:00–04:00
    "badge_scale": 100,         # percentage, 50–150; 100 = default (badges authored at 1x)
    "badge_spin_period": 20,    # seconds per full rotation, range 8–40
    "badge_spin_direction": 1,  # 1 = clockwise, -1 = counter-clockwise
}

_VALID_ROTATIONS = (0, 90, 180, 270)

_client = None
_installation_uuid: str | None = None


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
        log.warning("display_settings: Supabase init failed: %s", exc)
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
        log.warning("display_settings: no installation for key %r", _INSTALLATION_ID)
    except Exception as exc:
        log.warning("display_settings: UUID lookup failed: %s", exc)
    return None


def get_settings() -> dict[str, Any]:
    """Return display settings merged with defaults, loading from Supabase device_settings."""
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
                elif isinstance(default, int):
                    val = int(float(val))
            except (ValueError, TypeError):
                continue
            settings[key] = val
    except Exception as exc:
        log.warning("display_settings: get_settings failed: %s", exc)
    return settings


def apply_rotation(rotation: int) -> bool:
    """Apply display rotation immediately via wlr-randr. Returns True on success."""
    if rotation not in _VALID_ROTATIONS:
        log.warning("display_settings: invalid rotation %d — must be one of %s", rotation, _VALID_ROTATIONS)
        return False
    try:
        transform = "normal" if rotation == 0 else str(rotation)
        subprocess.run(
            ["wlr-randr", "--output", "HDMI-A-1", "--transform", transform],
            check=True,
            capture_output=True,
            timeout=10,
        )
        log.info("display_settings: applied rotation %d° via wlr-randr", rotation)
        return True
    except FileNotFoundError:
        log.warning("display_settings: wlr-randr not found — rotation not applied")
        return False
    except subprocess.CalledProcessError as exc:
        log.warning("display_settings: wlr-randr error: %s", exc.stderr.decode().strip())
        return False
    except Exception as exc:
        log.warning("display_settings: apply_rotation failed: %s", exc)
        return False


def save_settings(params: dict[str, Any]) -> bool:
    """Persist display settings to device_settings. Returns True on success."""
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
        return True
    except Exception as exc:
        log.warning("display_settings: save_settings failed: %s", exc)
        return False
