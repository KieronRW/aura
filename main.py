import json
import logging
import logging.handlers
import os
import http.server
import queue
import signal
import socket
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

_LOG_DIR = Path.home() / "aura" / "logs"
_LOG_FILE = _LOG_DIR / "aura.log"
_RECOGNITION_FILE = Path.home() / "aura" / "data" / "current_recognition.json"
_VERSION = "1.0.1"

# ---------------------------------------------------------------------------
# Logging — set up before any aura imports so all modules inherit the config
# ---------------------------------------------------------------------------

def _setup_logging() -> None:
    _LOG_DIR.mkdir(parents=True, exist_ok=True)
    root = logging.getLogger()
    root.setLevel(logging.DEBUG)

    fmt = logging.Formatter(
        "%(asctime)s %(levelname)-8s %(name)s — %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # Rotating file — 5 MB per file, keep 5 backups
    file_handler = logging.handlers.RotatingFileHandler(
        _LOG_FILE, maxBytes=5 * 1024 * 1024, backupCount=5, encoding="utf-8"
    )
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(fmt)

    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(fmt)

    root.addHandler(file_handler)
    root.addHandler(console_handler)


_setup_logging()
logger = logging.getLogger("aura.main")

# ---------------------------------------------------------------------------
# Aura imports (after logging is configured)
# ---------------------------------------------------------------------------

from aura.config.settings import (
    API_PORT,
    CAMERA_HEIGHT,
    CAMERA_WIDTH,
    FINGERPRINT_MATCH_THRESHOLD,
    GOOGLE_CREDENTIALS_PATH,
    GOOGLE_VISION_ENABLED,
    STATIC_IP,
    YOLO_CONFIDENCE,
)
from aura.core import api
from aura.core import detector as yolo_detector
from aura.core.discovery import DiscoveryService
from aura.core.camera import Camera, MotionState
from aura.core.cloud import is_connected, log_recognition, push_heartbeat, sync_settings, sync_vehicles, update_departure
from aura.core.display_server import DisplayServer
from aura.core.recognizer import Recognizer

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_RECOGNITION_COOLDOWN = 3        # seconds between recognition attempts
_VEHICLE_SYNC_INTERVAL = 300     # re-sync vehicles from Supabase every 5 minutes
_HEARTBEAT_INTERVAL    = 30      # push device_status heartbeat every 30 seconds
_BADGES_DIR = Path(__file__).parent / "assets" / "badges"
_BADGE_BASE_URL = "http://localhost:8080/assets/badges"
_DEFAULT_BADGE_URL = f"{_BADGE_BASE_URL}/default.png"

# ---------------------------------------------------------------------------
# Badge URL helper
# ---------------------------------------------------------------------------

def _badge_url(make: str | None) -> str:
    """Return the HTTP URL for a make's badge, falling back to default."""
    if not make:
        return _DEFAULT_BADGE_URL

    parts = make.lower().strip().replace("/", "-").split()

    # Try full slug first, then progressively shorter: "land-rover-evoque" -> "land-rover" -> "land"
    for i in range(len(parts), 0, -1):
        slug = "-".join(parts[:i])
        candidate = _BADGES_DIR / f"{slug}.png"
        if candidate.exists():
            return f"{_BADGE_BASE_URL}/{slug}.png"

    logger.debug("No badge file found for make '%s' — using default", make)
    return _DEFAULT_BADGE_URL


def _find_vehicle_by_make(make: str | None, vehicles: list[dict]) -> dict | None:
    """Match a Vision-returned make string against synced vehicles (case-insensitive substring)."""
    if not make or not vehicles:
        return None
    make_lower = make.lower()
    for v in vehicles:
        v_make = v.get("make", "").lower()
        if v_make and (v_make in make_lower or make_lower.startswith(v_make)):
            return v
    return None

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------

def _print_banner() -> None:
    google_creds_ok = os.path.exists(GOOGLE_CREDENTIALS_PATH)
    install_id = os.getenv("INSTALLATION_ID", "not set")
    lines = [
        "",
        "╔══════════════════════════════════════════════════╗",
        f"║  AURA v{_VERSION} — Vehicle Recognition             ║",
        "╠══════════════════════════════════════════════════╣",
        f"║  Camera       {CAMERA_WIDTH}x{CAMERA_HEIGHT:<32} ║",
        f"║  YOLO conf    {YOLO_CONFIDENCE:<35.2f} ║",
        f"║  FP threshold {FINGERPRINT_MATCH_THRESHOLD:<35.2f} ║",
        f"║  Google Vision {'ENABLED ' if GOOGLE_VISION_ENABLED else 'DISABLED':<34} ║",
        f"║  Vision creds  {'OK' if google_creds_ok else 'MISSING':<33} ║",
        f"║  Install ID    {install_id:<33} ║",
        f"║  API           {STATIC_IP}:{API_PORT:<25} ║",
        f"║  Display WS    ws://localhost:8765{'':<14} ║",
        f"║  Log           {str(_LOG_FILE):<33} ║",
        "╚══════════════════════════════════════════════════╝",
        "",
    ]
    for line in lines:
        print(line)

# ---------------------------------------------------------------------------
# JSON output helpers
# ---------------------------------------------------------------------------

def _write_recognition(payload: dict) -> None:
    _RECOGNITION_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = _RECOGNITION_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    tmp.replace(_RECOGNITION_FILE)


def _write_idle() -> None:
    _write_recognition({
        "state": "idle",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "matched_vehicle": None,
        "make": None,
        "model": None,
        "confidence": None,
        "method_used": None,
        "badge_path": None,
    })


def _write_result(result, vehicle: dict | None = None) -> None:
    vehicle = vehicle if vehicle is not None else result.matched_vehicle
    _write_recognition({
        "state": "recognized" if vehicle else "detected",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "matched_vehicle": {
            "id": vehicle["id"],
            "owner_name": vehicle["owner_name"],
            "owner_greeting": vehicle.get("owner_greeting"),
        } if vehicle else None,
        "make": result.make,
        "model": result.model,
        "confidence": result.confidence,
        "method_used": result.method_used,
        "badge_path": result.badge_path,
    })

# ---------------------------------------------------------------------------
# UDP trigger listener
# ---------------------------------------------------------------------------

_UDP_PORT = 9999


def _udp_listener(camera: "Camera", shutdown: dict) -> None:
    """Daemon thread: listens on UDP port 9999 for 'TRIGGER' to call force_presence()."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("", _UDP_PORT))
        sock.settimeout(0.5)
        logger.info("UDP trigger listener on port %d (send 'TRIGGER' to test)", _UDP_PORT)
        while not shutdown["requested"]:
            try:
                data, addr = sock.recvfrom(64)
            except TimeoutError:
                continue
            if data.strip() == b"TRIGGER":
                logger.info("TRIGGER received from %s — forcing PRESENCE state for 10 s", addr)
                camera.force_presence()

# ---------------------------------------------------------------------------
# HTTP test server
# ---------------------------------------------------------------------------

_HTTP_PORT = 9998
_TEST_IMAGE_PATH = Path.home() / "aura" / "test_vw_front.jpg"


def _make_http_handler(camera: "Camera", recognizer: "Recognizer", display_queue: "queue.Queue", synced_vehicles: list):
    class _Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/test-recognition":
                self._respond(404, {"error": "not found"})
                return

            import cv2

            if not _TEST_IMAGE_PATH.exists():
                self._respond(503, {"error": f"test image not found: {_TEST_IMAGE_PATH}"})
                return

            frame = cv2.imread(str(_TEST_IMAGE_PATH))
            if frame is None:
                self._respond(503, {"error": f"failed to load test image: {_TEST_IMAGE_PATH}"})
                return

            logger.info("HTTP test: using %s", _TEST_IMAGE_PATH.name)

            try:
                result = recognizer.recognize(frame, synced_vehicles, settings=_synced_settings)
            except Exception as exc:
                logger.exception("HTTP test: recognition error")
                self._respond(500, {"error": str(exc)})
                return

            if result is None:
                payload = {"state": "no_result"}
                display_queue.put(("idle",))
            else:
                vehicle = result.matched_vehicle or _find_vehicle_by_make(result.make, synced_vehicles)
                name = vehicle["owner_name"] if vehicle else "unknown"
                greeting = (vehicle.get("owner_greeting") if vehicle else None) or f"Welcome, {name}"
                badge_url = _badge_url(result.make)

                logger.info("HTTP test: badge_url=%s", badge_url)

                log_recognition(
                    result.make or "", result.model or "", result.confidence,
                    result.method_used, vehicle["id"] if vehicle else None,
                    image_frame=frame,
                )
                display_queue.put(("recognition", result.make or "", result.model or "", greeting, badge_url))

                payload = {
                    "state": "recognized" if vehicle else "detected",
                    "matched_vehicle": {
                        "id": vehicle["id"],
                        "owner_name": vehicle["owner_name"],
                        "owner_greeting": vehicle.get("owner_greeting"),
                    } if vehicle else None,
                    "make": result.make,
                    "model": result.model,
                    "confidence": result.confidence,
                    "method_used": result.method_used,
                }
                logger.info("HTTP test: recognised '%s' via %s (%.2f)", name, result.method_used, result.confidence)

            self._respond(200, payload)

        def _respond(self, code: int, body: dict):
            data = json.dumps(body, indent=2).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, fmt, *args):
            logger.debug("HTTP test: " + fmt, *args)

    return _Handler


def _start_http_server(camera: "Camera", recognizer: "Recognizer", display_queue: "queue.Queue", synced_vehicles: list) -> http.server.HTTPServer:
    handler = _make_http_handler(camera, recognizer, display_queue, synced_vehicles)
    server = http.server.HTTPServer(("", _HTTP_PORT), handler)
    t = threading.Thread(target=server.serve_forever, daemon=True, name="http-test")
    t.start()
    logger.info("HTTP test server on http://localhost:%d/test-recognition", _HTTP_PORT)
    return server

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    _print_banner()
    logger.info("AURA v%s starting up", _VERSION)

    _start_time = time.monotonic()
    _installation_key = os.getenv("INSTALLATION_ID", "")
    _state: dict = {
        "current_state":               "idle",
        "vehicle_present":             False,
        "last_recognized_make":        None,
        "last_recognized_owner":       None,
        "last_recognition_confidence": None,
        "camera_ok":                   False,
        "display_clients":             0,
        "supabase_ok":                 False,
        "uptime_seconds":              0.0,
        "synced_vehicles":             [],
        "recent_events":               [],
        "trigger_recognition_cb":      None,
        "force_idle_cb":               None,
        "force_recognition_cb":        None,
        "installation_key":            _installation_key,
        "name":                        socket.gethostname(),
        "software_version":            _VERSION,
    }
    api.init(_state)

    # Start display WebSocket server
    display = DisplayServer()
    try:
        display.start()
        logger.info("Display server started on ws://localhost:8765")
    except Exception:
        logger.exception("Failed to start display server — aborting")
        sys.exit(1)

    _state["force_idle_cb"] = display.send_idle
    _state["force_recognition_cb"] = display.send_recognition

    # Start FastAPI server (non-critical — won't abort startup on failure)
    try:
        threading.Thread(
            target=api.start_server,
            args=("0.0.0.0", API_PORT),
            daemon=True,
            name="api",
        ).start()
        logger.info("API server starting on http://0.0.0.0:%d", API_PORT)
    except Exception:
        logger.warning("Failed to start API server — continuing without API")

    _discovery = DiscoveryService(
        installation_key=_installation_key,
        version=_VERSION,
        port=API_PORT,
    )
    _discovery.start()

    # Start camera
    camera = Camera()
    try:
        camera.start()
        logger.info("Camera service started")
    except Exception:
        logger.exception("Failed to start camera — aborting")
        sys.exit(1)

    _state["camera_ok"] = True
    _state["trigger_recognition_cb"] = camera.force_presence

    _synced_vehicles = sync_vehicles()
    _synced_settings = sync_settings()
    logger.info(
        "Supabase sync: %d vehicles, %d settings",
        len(_synced_vehicles), len(_synced_settings),
    )
    _state["supabase_ok"] = is_connected()
    _state["synced_vehicles"] = _synced_vehicles

    recognizer = Recognizer()
    _display_queue: queue.Queue = queue.Queue()

    http_server = _start_http_server(camera, recognizer, _display_queue, _synced_vehicles)

    # Graceful shutdown
    _shutdown = {"requested": False}

    kb_thread = threading.Thread(
        target=_udp_listener,
        args=(camera, _shutdown),
        daemon=True,
        name="udp-trigger",
    )
    kb_thread.start()

    def _handle_signal(sig, _frame):
        logger.info("Shutdown signal received (%s)", signal.Signals(sig).name)
        _shutdown["requested"] = True

    signal.signal(signal.SIGINT, _handle_signal)
    signal.signal(signal.SIGTERM, _handle_signal)

    logger.info("Main loop running — press Ctrl+C to stop")
    _write_idle()

    last_recognition_at = 0.0
    last_recognition_sent_at = 0.0
    last_state_log_at = 0.0
    last_heartbeat_at = 0.0
    last_recognized_make: str | None = None
    last_hold_check_at: float = 0.0
    gone_since: float | None = None
    last_event_id: int | None = None
    last_vehicle_sync_at: float = time.monotonic()

    # Startup scan: recognise any car already in frame
    logger.info("Startup: running initial recognition scan")
    time.sleep(3)
    startup_frame = camera.get_frame()
    if startup_frame is not None:
        try:
            startup_result = recognizer.recognize(startup_frame, _synced_vehicles, settings=_synced_settings)
            if startup_result and startup_result.make:
                vehicle = startup_result.matched_vehicle or _find_vehicle_by_make(startup_result.make, _synced_vehicles)
                name = vehicle["owner_name"] if vehicle else "unknown"
                logger.info("Startup: recognised %s (%s) conf=%.2f", startup_result.make, name, startup_result.confidence)
                greeting = (vehicle.get("owner_greeting") if vehicle else None) or f"Welcome, {name}"
                badge_url = _badge_url(startup_result.make)
                log_recognition(
                    startup_result.make or "", startup_result.model or "", startup_result.confidence,
                    startup_result.method_used, vehicle["id"] if vehicle else None,
                    image_frame=frame,
                )
                display.send_recognition(make=startup_result.make or "", model=startup_result.model or "", greeting=greeting, badge_url=badge_url)
                last_recognition_sent_at = time.monotonic()
                last_recognized_make = startup_result.make or ""
                last_hold_check_at = 0.0
                camera.set_hold_reference(True)
                _state["current_state"] = "recognized" if vehicle else "detected"
                _state["vehicle_present"] = True
                _state["last_recognized_make"] = startup_result.make
                _state["last_recognized_owner"] = name if vehicle else None
                _state["last_recognition_confidence"] = startup_result.confidence
            else:
                logger.info("Startup: no vehicle detected")
        except Exception:
            logger.exception("Startup scan failed")
    else:
        logger.info("Startup: camera not ready")

    try:
        while not _shutdown["requested"]:

            # Drain display commands queued by the HTTP test endpoint
            while True:
                try:
                    cmd = _display_queue.get_nowait()
                except queue.Empty:
                    break
                if cmd[0] == "recognition":
                    display.send_recognition(make=cmd[1], model=cmd[2], greeting=cmd[3], badge_url=cmd[4])
                    last_recognition_sent_at = time.monotonic()
                elif cmd[0] == "idle":
                    if time.monotonic() - last_recognition_sent_at >= 10.0:
                        display.send_idle()

            now_mono = time.monotonic()

            # ── Periodic vehicle sync (every 5 minutes) ──────────────────────
            if now_mono - last_vehicle_sync_at >= _VEHICLE_SYNC_INTERVAL:
                last_vehicle_sync_at = now_mono
                fresh = sync_vehicles()
                if fresh:
                    _synced_vehicles = fresh
                    _state["synced_vehicles"] = _synced_vehicles
                    logger.info("Vehicle sync: %d vehicles refreshed", len(_synced_vehicles))
                else:
                    logger.warning("Vehicle sync returned empty — retaining previous data")

            # ── Periodic state log ────────────────────────────────────────────
            if now_mono - last_state_log_at >= 5.0:
                state = camera.get_motion_state()
                logger.info("Motion state: %s", state.value)
                last_state_log_at = now_mono
                _state["uptime_seconds"] = now_mono - _start_time
                _state["display_clients"] = display.client_count

            # ── Heartbeat (every 30 s) ────────────────────────────────────────
            if now_mono - last_heartbeat_at >= _HEARTBEAT_INTERVAL:
                last_heartbeat_at = now_mono
                push_heartbeat(
                    camera_ok=_state["camera_ok"],
                    display_clients=_state["display_clients"],
                    current_state=_state["current_state"],
                    software_version=_VERSION,
                )

            # ── YOLO hold: if we already recognised a car, skip motion detection ──
            #    last_hold_check_at is reset to 0 on new recognition so the first
            #    hold check fires on the very next iteration (~250 ms later).
            if last_recognized_make is not None:
                if now_mono - last_hold_check_at >= 3.0:
                    last_hold_check_at = now_mono
                    hold_frame = camera.get_frame()
                    if hold_frame is not None:
                        det = yolo_detector.detect(hold_frame)
                        if det.is_vehicle:
                            gone_since = None
                            logger.info(
                                "Vehicle still present (YOLO conf=%.2f) — holding badge",
                                det.confidence,
                            )
                            # Keepalive: re-send badge every 30 s to prevent display timeout
                            if now_mono - last_recognition_sent_at >= 30.0:
                                badge_url = _badge_url(last_recognized_make)
                                display.send_recognition(make=last_recognized_make, model="", greeting="", badge_url=badge_url)
                                last_recognition_sent_at = now_mono
                                logger.info("Re-sent badge to display (keepalive)")
                        else:
                            if gone_since is None:
                                gone_since = now_mono
                                logger.info("YOLO lost vehicle — starting 5 s departure timer")
                            elif now_mono - gone_since >= 5.0:
                                logger.info("Vehicle departed — returning to idle")
                                if last_event_id is not None:
                                    update_departure(last_event_id)
                                    last_event_id = None
                                last_recognized_make = None
                                gone_since = None
                                camera.set_hold_reference(False)
                                _write_idle()
                                display.send_idle()
                                _state["current_state"] = "idle"
                                _state["vehicle_present"] = False

                time.sleep(0.25)
                continue

            # ── Periodic idle YOLO scan (every 60 s) ─────────────────────────
            if now_mono - last_hold_check_at >= 60.0:
                last_hold_check_at = now_mono
                idle_frame = camera.get_frame()
                if idle_frame is not None:
                    idle_det = yolo_detector.detect(idle_frame)
                    if idle_det.is_vehicle:
                        logger.info("Idle scan: vehicle detected (YOLO conf=%.2f) — triggering recognition", idle_det.confidence)
                        camera.force_presence(duration=10.0)
                        camera.set_hold_reference(True)

            # ── Normal motion-based detection ─────────────────────────────────
            state = camera.get_motion_state()
            if state != MotionState.PRESENCE:
                if state == MotionState.IDLE:
                    _write_idle()
                    if time.monotonic() - last_recognition_sent_at >= 10.0:
                        display.send_idle()
                    _state["current_state"] = "idle"
                    _state["vehicle_present"] = False
                time.sleep(0.25)
                continue

            now = time.monotonic()
            if now - last_recognition_at < _RECOGNITION_COOLDOWN:
                time.sleep(0.25)
                continue

            last_recognition_at = now

            logger.info("Vehicle presence confirmed — capturing still")
            frame = camera.capture_still()
            if frame is None:
                logger.warning("capture_still returned None — skipping recognition")
                time.sleep(0.25)
                continue

            logger.info("Running recognition pipeline")
            try:
                result = recognizer.recognize(frame, _synced_vehicles, settings=_synced_settings)
            except Exception:
                logger.exception("Recognition pipeline error")
                time.sleep(0.25)
                continue

            if result is None:
                logger.info("Recognizer returned no result")
                _write_idle()
                if time.monotonic() - last_recognition_sent_at >= 10.0:
                    display.send_idle()
            else:
                vehicle = result.matched_vehicle or _find_vehicle_by_make(result.make, _synced_vehicles)
                name = vehicle["owner_name"] if vehicle else "unknown"
                logger.info(
                    "Recognition complete — vehicle='%s' make='%s' method=%s conf=%.2f",
                    name, result.make, result.method_used, result.confidence,
                )
                _write_result(result, vehicle)

                greeting = (vehicle.get("owner_greeting") if vehicle else None) or f"Welcome, {name}"
                badge_url = _badge_url(result.make)

                # Only log a new event if this is a new vehicle arrival
                if last_event_id is None or (result.make and result.make != last_recognized_make):
                    event = log_recognition(
                        result.make or "", result.model or "", result.confidence,
                        result.method_used, vehicle["id"] if vehicle else None,
                        image_frame=frame,
                    )
                    last_event_id = event["id"] if event else None

                display.send_recognition(
                    make=result.make or "",
                    model=result.model or "",
                    greeting=greeting,
                    badge_url=badge_url,
                )
                last_recognition_sent_at = time.monotonic()
                last_recognized_make = result.make or ""
                last_hold_check_at = 0.0  # trigger immediate YOLO hold check on next iteration
                gone_since = None
                camera.set_hold_reference(True)

                _state["current_state"] = "recognized" if vehicle else "detected"
                _state["vehicle_present"] = True
                _state["last_recognized_make"] = result.make
                _state["last_recognized_owner"] = name if vehicle else None
                _state["last_recognition_confidence"] = result.confidence
                _state["recent_events"] = ([{
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "make": result.make,
                    "model": result.model,
                    "confidence": result.confidence,
                    "method_used": result.method_used,
                    "owner_name": name if vehicle else None,
                }] + _state["recent_events"])[:20]

    finally:
        _discovery.stop()
        http_server.shutdown()
        kb_thread.join(timeout=1)
        logger.info("Stopping camera service")
        camera.stop()
        _write_idle()
        display.send_idle()
        display.stop()
        logger.info("AURA shut down cleanly")


if __name__ == "__main__":
    main()
