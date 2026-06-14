import asyncio
import logging
import shlex
import subprocess
import threading
import time as _time
from typing import Any, Optional

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

logger = logging.getLogger(__name__)

app = FastAPI(title="AURA", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

_state: dict[str, Any] = {}


def init(shared_state: dict[str, Any]) -> None:
    global _state
    _state = shared_state


def start_server(host: str, port: int) -> None:
    config = uvicorn.Config(app, host=host, port=port, log_level="warning", access_log=False)
    server = uvicorn.Server(config)
    server.run()


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

@app.get("/health")
def get_health():
    return {
        "camera_ok":       _state.get("camera_ok", False),
        "display_clients": _state.get("display_clients", 0),
        "supabase_ok":     _state.get("supabase_ok", False),
        "uptime_seconds":  _state.get("uptime_seconds", 0.0),
    }


# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

@app.get("/status")
def get_status():
    return {
        "current_state":               _state.get("current_state", "idle"),
        "vehicle_present":             _state.get("vehicle_present", False),
        "last_recognized_make":        _state.get("last_recognized_make"),
        "last_recognized_owner":       _state.get("last_recognized_owner"),
        "last_recognition_confidence": _state.get("last_recognition_confidence"),
        "camera_ok":                   _state.get("camera_ok", False),
        "display_clients":             _state.get("display_clients", 0),
        "supabase_ok":                 _state.get("supabase_ok", False),
        "uptime_seconds":              _state.get("uptime_seconds", 0.0),
    }


# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

@app.get("/vehicles")
def get_vehicles():
    return _state.get("synced_vehicles", [])


@app.get("/events")
def get_events():
    return _state.get("recent_events", [])


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

@app.post("/trigger")
def trigger_recognition():
    cb = _state.get("trigger_recognition_cb")
    if cb is None:
        raise HTTPException(503, detail="System not ready")
    try:
        cb()
    except Exception as exc:
        logger.warning("trigger_recognition_cb failed: %s", exc)
        raise HTTPException(500, detail=str(exc))
    return {"ok": True}


@app.post("/idle")
def force_idle():
    cb = _state.get("force_idle_cb")
    if cb is None:
        raise HTTPException(503, detail="System not ready")
    try:
        cb()
    except Exception as exc:
        logger.warning("force_idle_cb failed: %s", exc)
        raise HTTPException(500, detail=str(exc))
    return {"ok": True}


class DisplayPayload(BaseModel):
    make: str
    model: str = ""
    greeting: str = ""
    badge_url: str = ""


@app.post("/display")
def force_display(payload: DisplayPayload):
    cb = _state.get("force_recognition_cb")
    if cb is None:
        raise HTTPException(503, detail="System not ready")
    try:
        cb(payload.make, payload.model or None, payload.greeting, payload.badge_url or None)
    except Exception as exc:
        logger.warning("force_recognition_cb failed: %s", exc)
        raise HTTPException(500, detail=str(exc))
    return {"ok": True}


# ---------------------------------------------------------------------------
# Discovery / Onboarding
# ---------------------------------------------------------------------------

@app.get("/info")
def get_info():
    return {
        "installation_key": _state.get("installation_key", ""),
        "name":             _state.get("name", ""),
        "software_version": _state.get("software_version", ""),
        "camera_ok":        _state.get("camera_ok", False),
        "is_online":        True,
    }


class ClaimPayload(BaseModel):
    supabase_url: str
    supabase_key: str
    installation_key: str


@app.post("/claim")
def claim_installation(payload: ClaimPayload):
    try:
        from supabase import create_client
        client = create_client(payload.supabase_url, payload.supabase_key)

        response = (
            client.table("installations")
            .select("id, status")
            .eq("installation_key", payload.installation_key)
            .execute()
        )
        if not response.data:
            return {"ok": False, "error": "Installation not found"}

        if response.data[0].get("status") == "active":
            return {"ok": False, "error": "Installation already claimed"}

        client.table("installations").update({"status": "active"}).eq(
            "installation_key", payload.installation_key
        ).execute()

        return {"ok": True}
    except Exception as exc:
        logger.warning("Claim failed: %s", exc)
        return {"ok": False, "error": str(exc)}


# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------

class CameraSettingsPayload(BaseModel):
    brightness: Optional[int] = None           # 0–100
    contrast: Optional[int] = None             # 0–100
    exposure: Optional[int] = None             # -50 to 50
    horizontal_flip: Optional[bool] = None
    vertical_flip: Optional[bool] = None
    rotation: Optional[int] = None             # 0, 90, 180, 270
    motion_sensitivity: Optional[int] = None   # 0–100
    sharpness: Optional[int] = None            # 0–100
    denoise_mode: Optional[str] = None         # "off" | "fast" | "high_quality"
    awb_mode: Optional[str] = None             # "auto" | "daylight" | "cloudy" | "tungsten" | "fluorescent" | "indoor" | "incandescent"
    hdr_mode: Optional[str] = None             # "off" | "single" | "multi" | "night"
    af_mode: Optional[str] = None              # "continuous" | "auto" | "manual"
    lens_position: Optional[float] = None      # 0.0 (infinity) – 10.0 (macro)
    flicker_period_us: Optional[int] = None    # 0=off | 20000=50Hz | 16667=60Hz


@app.get("/camera/settings")
def get_camera_settings():
    from aura.core import camera_settings
    return camera_settings.get_settings()


@app.post("/camera/settings")
def post_camera_settings(payload: CameraSettingsPayload):
    from aura.core import camera_settings
    params = {k: v for k, v in payload.model_dump().items() if v is not None}
    if not params:
        raise HTTPException(400, detail="No settings provided")
    camera = _state.get("camera")
    if camera is not None:
        camera_settings.apply_settings(params, camera)
    saved = camera_settings.save_settings(params)
    return {"ok": True, "saved": saved, "applied": camera is not None}


@app.get("/camera/stream")
async def camera_stream():
    import cv2
    camera = _state.get("camera")
    if camera is None:
        raise HTTPException(503, detail="Camera not available")

    async def generate():
        while True:
            frame = camera.get_frame()
            if frame is not None:
                ok, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 70])
                if ok:
                    data = buf.tobytes()
                    yield (
                        b"--frame\r\n"
                        b"Content-Type: image/jpeg\r\n"
                        b"Content-Length: " + str(len(data)).encode() + b"\r\n\r\n"
                        + data + b"\r\n"
                    )
            await asyncio.sleep(0.1)

    return StreamingResponse(
        generate(),
        media_type="multipart/x-mixed-replace; boundary=frame",
    )


# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

def _prefix_to_mask(prefix: int) -> str:
    mask = (0xFFFFFFFF << (32 - max(0, min(32, prefix)))) & 0xFFFFFFFF
    return ".".join(str((mask >> (8 * i)) & 0xFF) for i in [3, 2, 1, 0])


def _mask_to_prefix(mask: str) -> int:
    try:
        parts = [int(x) for x in mask.split(".")]
        return sum(bin(p).count("1") for p in parts)
    except (ValueError, AttributeError):
        return 24


def _active_connection() -> tuple[str, str, str] | None:
    """Return (conn_name, device, conn_type) for the first active ethernet/wifi connection."""
    result = subprocess.run(
        ["nmcli", "-t", "--escape", "no", "-f", "NAME,DEVICE,TYPE,STATE",
         "connection", "show", "--active"],
        capture_output=True, text=True, timeout=10,
    )
    for line in result.stdout.strip().splitlines():
        parts = line.rsplit(":", 3)
        if len(parts) < 4:
            continue
        name, device, t, state = parts[0], parts[1], parts[2], parts[3]
        if state == "activated" and t in ("802-3-ethernet", "802-11-wireless"):
            conn_type = "wifi" if "wireless" in t else "ethernet"
            return name, device, conn_type
    return None


@app.get("/network/settings")
def get_network_settings():
    try:
        conn = _active_connection()
        if conn is None:
            raise HTTPException(503, detail="No active network connection found")
        conn_name, device, conn_type = conn

        method_out = subprocess.run(
            ["nmcli", "--get-values", "ipv4.method", "connection", "show", conn_name],
            capture_output=True, text=True, timeout=10,
        ).stdout.strip()
        method = "static" if method_out == "manual" else "dhcp"

        dev_out = subprocess.run(
            ["nmcli", "-t", "--escape", "no", "-f", "IP4.ADDRESS,IP4.GATEWAY,IP4.DNS",
             "device", "show", device],
            capture_output=True, text=True, timeout=10,
        )

        ip_address, prefix, gateway = "", 24, ""
        dns_servers: list[str] = []

        for line in dev_out.stdout.strip().splitlines():
            if ":" not in line:
                continue
            key, _, value = line.partition(":")
            key, value = key.strip(), value.strip()
            if key.startswith("IP4.ADDRESS") and value:
                if "/" in value:
                    ip_address, p = value.rsplit("/", 1)
                    prefix = int(p)
                else:
                    ip_address = value
            elif key == "IP4.GATEWAY" and value:
                gateway = value
            elif key.startswith("IP4.DNS") and value:
                dns_servers.append(value)

        return {
            "interface": device,
            "connection_type": conn_type,
            "connection_name": conn_name,
            "method": method,
            "ip_address": ip_address,
            "subnet_mask": _prefix_to_mask(prefix),
            "gateway": gateway,
            "dns_primary": dns_servers[0] if dns_servers else "",
            "dns_secondary": dns_servers[1] if len(dns_servers) > 1 else "",
        }
    except HTTPException:
        raise
    except FileNotFoundError:
        raise HTTPException(501, detail="nmcli not available on this system")
    except Exception as exc:
        logger.exception("get_network_settings failed")
        raise HTTPException(500, detail=str(exc))


class NetworkSettingsPayload(BaseModel):
    method: str                  # "dhcp" or "static"
    ip_address: str = ""
    subnet_mask: str = ""
    gateway: str = ""
    dns_primary: str = ""
    dns_secondary: str = ""


@app.post("/network/settings")
def post_network_settings(payload: NetworkSettingsPayload):
    if payload.method not in ("dhcp", "static"):
        raise HTTPException(400, detail="method must be 'dhcp' or 'static'")

    try:
        conn = _active_connection()
        if conn is None:
            raise HTTPException(503, detail="No active network connection found")
        conn_name, _device, _conn_type = conn

        if payload.method == "dhcp":
            # Use shell=True so empty-string args clear the nmcli fields exactly as
            # they would when run interactively; list-form empty strings can be a no-op.
            subprocess.run(
                "sudo nmcli connection modify "
                + shlex.quote(conn_name)
                + ' ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns ""',
                shell=True, check=True, capture_output=True, text=True, timeout=10,
            )
        else:
            if not all([payload.ip_address, payload.subnet_mask, payload.gateway]):
                raise HTTPException(
                    400, detail="ip_address, subnet_mask, and gateway are required"
                )
            prefix = _mask_to_prefix(payload.subnet_mask)
            cidr = f"{payload.ip_address}/{prefix}"
            dns_parts = [d for d in [payload.dns_primary, payload.dns_secondary] if d]
            dns_str = ",".join(dns_parts)

            cmd = [
                "sudo", "nmcli", "connection", "modify", conn_name,
                "ipv4.method", "manual",
                "ipv4.addresses", cidr,
                "ipv4.gateway", payload.gateway,
                "ipv4.dns", dns_str,
            ]
            subprocess.run(cmd, check=True, capture_output=True, timeout=10)

        # Restart the connection in a background thread so the HTTP response escapes
        # first. connection down + up forces NM to re-read the modified profile;
        # connection up alone on an already-active link can be a no-op.
        def _apply() -> None:
            _time.sleep(1.0)
            subprocess.run(
                ["sudo", "nmcli", "connection", "down", conn_name],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10,
            )
            subprocess.run(
                ["sudo", "nmcli", "connection", "up", conn_name],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20,
            )

        threading.Thread(target=_apply, daemon=True).start()
        return {"ok": True}

    except HTTPException:
        raise
    except FileNotFoundError:
        raise HTTPException(501, detail="nmcli not available on this system")
    except subprocess.CalledProcessError as exc:
        logger.warning("nmcli error: %s", exc.stderr)
        raise HTTPException(500, detail=f"nmcli error: {exc.stderr.strip()}")
    except Exception as exc:
        logger.exception("post_network_settings failed")
        raise HTTPException(500, detail=str(exc))


# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

class DisplaySettingsPayload(BaseModel):
    display_rotation: Optional[int] = None  # 0, 90, 180, 270


@app.get("/display/settings")
def get_display_settings():
    from aura.core import display_settings
    return display_settings.get_settings()


@app.post("/display/settings")
def post_display_settings(payload: DisplaySettingsPayload):
    from aura.core import display_settings
    params = {k: v for k, v in payload.model_dump().items() if v is not None}
    if not params:
        raise HTTPException(400, detail="No settings provided")
    saved = display_settings.save_settings(params)
    applied = False
    if "display_rotation" in params:
        applied = display_settings.apply_rotation(params["display_rotation"])
    return {"ok": True, "saved": saved, "applied": applied}


# ---------------------------------------------------------------------------
# Recognition
# ---------------------------------------------------------------------------

class RecognitionSettingsPayload(BaseModel):
    vision_confidence_gate: Optional[float] = None
    auto_learn_min: Optional[float] = None
    auto_learn_max: Optional[float] = None
    offline_fp_threshold: Optional[float] = None


@app.get("/recognition/settings")
def get_recognition_settings():
    from aura.core import recognition_settings
    return recognition_settings.get_settings()


@app.post("/recognition/settings")
def post_recognition_settings(payload: RecognitionSettingsPayload):
    from aura.core import recognition_settings
    params = {k: v for k, v in payload.model_dump().items() if v is not None}
    if not params:
        raise HTTPException(400, detail="No settings provided")
    saved = recognition_settings.save_settings(params)
    return {"ok": True, "saved": saved}
