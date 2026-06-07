import asyncio
import logging
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
