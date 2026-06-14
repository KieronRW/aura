import logging
import os
from pathlib import Path
from typing import Any

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / "config" / ".env")

log = logging.getLogger(__name__)

_SUPABASE_URL = os.getenv("SUPABASE_URL", "")
_SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
_INSTALLATION_ID = os.getenv("INSTALLATION_ID", "")

# Defaults returned when Supabase is unreachable
DEFAULTS: dict[str, Any] = {
    "brightness": 50,           # 0–100
    "contrast": 50,             # 0–100
    "exposure": 0,              # -50 to 50
    "horizontal_flip": False,
    "vertical_flip": False,
    "rotation": 0,              # 0, 90, 180, 270
    "motion_sensitivity": 50,   # 0–100 (higher = more sensitive)
    "sharpness": 50,            # 0–100 (50 = libcamera default 1.0)
    "denoise_mode": "fast",     # "off" | "fast" | "high_quality"
    "awb_mode": "auto",         # "auto" | "daylight" | "cloudy" | "tungsten" | "fluorescent" | "indoor" | "incandescent"
    "hdr_mode": "off",          # "off" | "single" | "multi" | "night"
    "af_mode": "continuous",    # "continuous" | "auto" | "manual"
    "lens_position": 0.0,       # 0.0 (infinity) – 10.0 (macro); effective only in manual af_mode
    "flicker_period_us": 0,     # 0=off | 20000=50Hz | 16667=60Hz
}

_AWB_MODE_MAP: dict[str, int] = {
    "auto": 0, "incandescent": 1, "tungsten": 2,
    "fluorescent": 3, "indoor": 4, "daylight": 5, "cloudy": 6,
}
_HDR_MODE_MAP: dict[str, int] = {"off": 0, "single": 3, "multi": 2, "night": 4}
_AF_MODE_MAP: dict[str, int] = {"manual": 0, "auto": 1, "continuous": 2}
_DENOISE_MODE_MAP: dict[str, int] = {"off": 0, "fast": 1, "high_quality": 2}

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
        log.warning("camera_settings: Supabase init failed: %s", exc)
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
        log.warning("camera_settings: no installation for key %r", _INSTALLATION_ID)
    except Exception as exc:
        log.warning("camera_settings: UUID lookup failed: %s", exc)
    return None


def _sensitivity_to_threshold(sensitivity: int) -> float:
    """Map motion_sensitivity 0–100 to a MOTION_THRESHOLD pixel-area value.

    At sensitivity=50 the threshold matches the default (200 px²).
    Higher sensitivity → lower threshold (detects finer motion).
    """
    sensitivity = max(0, min(100, sensitivity))
    # Exponential scale: threshold = 200 * 50^((50 - s) / 50)
    return round(200.0 * (50.0 ** ((50 - sensitivity) / 50.0)), 2)


def get_settings() -> dict[str, Any]:
    """Return camera settings merged with defaults, loading from Supabase device_settings."""
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
        log.warning("camera_settings: get_settings failed: %s", exc)
    return settings


def save_settings(params: dict[str, Any]) -> bool:
    """Persist camera settings to device_settings. Returns True on success."""
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
        log.warning("camera_settings: save_settings failed: %s", exc)
        return False


def apply_settings(params: dict[str, Any], camera) -> None:
    """Apply camera settings to the live Camera instance."""
    controls: dict[str, Any] = {}

    if "brightness" in params:
        brightness = max(0, min(100, int(params["brightness"])))
        controls["Brightness"] = round((brightness - 50) / 50.0, 4)

    if "contrast" in params:
        contrast = max(0, min(100, int(params["contrast"])))
        # Piecewise: 0→0.0, 50→1.0 (neutral/default), 100→32.0
        if contrast <= 50:
            picam_contrast = contrast / 50.0
        else:
            picam_contrast = 1.0 + (contrast - 50) * 31.0 / 50.0
        controls["Contrast"] = round(picam_contrast, 4)

    if "exposure" in params:
        exposure = max(-50, min(50, int(params["exposure"])))
        controls["ExposureValue"] = round(exposure * 8.0 / 50.0, 4)

    if "sharpness" in params:
        s = max(0, min(100, int(params["sharpness"])))
        sharpness_f = (s / 50.0) if s <= 50 else (1.0 + (s - 50) * 15.0 / 50.0)
        controls["Sharpness"] = round(sharpness_f, 4)

    if "denoise_mode" in params:
        v = _DENOISE_MODE_MAP.get(str(params["denoise_mode"]).lower())
        if v is not None:
            controls["NoiseReductionMode"] = v

    if "awb_mode" in params:
        v = _AWB_MODE_MAP.get(str(params["awb_mode"]).lower())
        if v is not None:
            controls["AwbMode"] = v

    if "hdr_mode" in params:
        v = _HDR_MODE_MAP.get(str(params["hdr_mode"]).lower())
        if v is not None:
            controls["HdrMode"] = v

    if "af_mode" in params:
        v = _AF_MODE_MAP.get(str(params["af_mode"]).lower())
        if v is not None:
            controls["AfMode"] = v

    if "lens_position" in params:
        controls["LensPosition"] = float(params["lens_position"])

    if "flicker_period_us" in params:
        period = int(params["flicker_period_us"])
        if period == 0:
            controls["AeFlickerMode"] = 0
        else:
            controls["AeFlickerMode"] = 1
            controls["AeFlickerPeriod"] = period

    if controls:
        camera.apply_controls(controls)

    needs_transform = any(k in params for k in ("horizontal_flip", "vertical_flip", "rotation"))
    if needs_transform:
        hflip = bool(params.get("horizontal_flip", camera._hflip))
        vflip = bool(params.get("vertical_flip", camera._vflip))
        rotation = int(params.get("rotation", camera._rotation))
        if rotation not in (0, 90, 180, 270):
            log.warning("camera_settings: invalid rotation %d — ignoring", rotation)
        elif hflip != camera._hflip or vflip != camera._vflip or rotation != camera._rotation:
            camera.set_transform(hflip, vflip, rotation)

    if "motion_sensitivity" in params:
        sensitivity = max(0, min(100, int(params["motion_sensitivity"])))
        threshold = _sensitivity_to_threshold(sensitivity)
        camera.set_motion_threshold(threshold)
