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
_VERSION = "1.0.0"

# ---------------------------------------------------------------------------
# Logging — set up before any aura imports so all modules inherit the config
# ---------------------------------------------------------------------------

def _setup_logging() -> None:
    _LOG_DIR.mkdir(parents=True, exist_ok=True)
    root = logging.getLogger()
    root.setLevel(logging.DEBUG)

    fmt = logging.Formatter(
        "%(asctime)s  %(levelname)-8s  %(name)s — %(message)s",
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
    DATABASE_PATH,
    FINGERPRINT_MATCH_THRESHOLD,
    GOOGLE_CREDENTIALS_PATH,
    GOOGLE_VISION_ENABLED,
    STATIC_IP,
    YOLO_CONFIDENCE,
)
from aura.core import database as db
from aura.core import detector as yolo_detector
from aura.core.camera import Camera, MotionState
from aura.core.display_server import DisplayServer
from aura.core.recognizer import Recognizer

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_RECOGNITION_COOLDOWN = 3  # seconds between recognition attempts

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
    slug = make.lower().strip().split()[0].replace("/", "-")
    candidate = _BADGES_DIR / f"{slug}.png"
    if candidate.exists():
        return f"{_BADGE_BASE_URL}/{slug}.png"
    logger.debug("No badge file found for make '%s' (checked %s) — using default", make, candidate)
    return _DEFAULT_BADGE_URL


# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------

def _print_banner() -> None:
    google_creds_ok = os.path.exists(GOOGLE_CREDENTIALS_PATH)
    db_path = os.path.expanduser(DATABASE_PATH)

    lines = [
        "",
        "╔══════════════════════════════════════════════════╗",
        f"║          AURA  v{_VERSION}  —  Vehicle Recognition       ║",
        "╠══════════════════════════════════════════════════╣",
        f"║  Camera       {CAMERA_WIDTH}x{CAMERA_HEIGHT:<34} ║",
        f"║  YOLO conf    {YOLO_CONFIDENCE:<35.2f} ║",
        f"║  FP threshold {FINGERPRINT_MATCH_THRESHOLD:<35.2f} ║",
        f"║  Google Vision {'ENABLED ' if GOOGLE_VISION_ENABLED else 'DISABLED':<34} ║",
        f"║  Vision creds  {'OK' if google_creds_ok else 'MISSING':<33} ║",
        f"║  Database     {db_path:<34} ║",
        f"║  API          {STATIC_IP}:{API_PORT:<26} ║",
        f"║  Display WS   ws://localhost:8765{'':<18} ║",
        f"║  Log          {str(_LOG_FILE):<34} ║",
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


def _write_result(result) -> None:
    vehicle = result.matched_vehicle
    _write_recognition({
        "state": "recognized" if vehicle else "detected",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "matched_vehicle": {
            "id": vehicle["id"],
            "name": vehicle["name"],
            "greeting": vehicle.get("greeting"),
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


def _make_http_handler(camera: "Camera", recognizer: "Recognizer", display_queue: "queue.Queue"):
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
                result = recognizer.recognize(frame)
            except Exception as exc:
                logger.exception("HTTP test: recognition error")
                self._respond(500, {"error": str(exc)})
                return

            if result is None:
                payload = {"state": "no_result"}
                display_queue.put(("idle",))
            else:
                vehicle  = result.matched_vehicle
                name     = vehicle["name"] if vehicle else "unknown"
                greeting = (vehicle.get("greeting") if vehicle else None) or f"Welcome, {name}"
                badge_url = _badge_url(result.make)
                logger.info("HTTP test: badge_url=%s", badge_url)
                display_queue.put(("recognition", result.make or "", result.model or "", greeting, badge_url))
                payload = {
                    "state": "recognized" if vehicle else "detected",
                    "matched_vehicle": {
                        "id": vehicle["id"],
                        "name": vehicle["name"],
                        "greeting": vehicle.get("greeting"),
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


def _start_http_server(camera: "Camera", recognizer: "Recognizer", display_queue: "queue.Queue") -> http.server.HTTPServer:
    handler = _make_http_handler(camera, recognizer, display_queue)
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

    # Initialise database
    try:
        db.init_db()
        logger.info("Database initialised at %s", DATABASE_PATH)
    except Exception:
        logger.exception("Failed to initialise database — aborting")
        sys.exit(1)

    # Start display WebSocket server
    display = DisplayServer()
    try:
        display.start()
        logger.info("Display server started on ws://localhost:8765")
    except Exception:
        logger.exception("Failed to start display server — aborting")
        sys.exit(1)

    # Start camera
    camera = Camera()
    try:
        camera.start()
        logger.info("Camera service started")
    except Exception:
        logger.exception("Failed to start camera — aborting")
        sys.exit(1)

    recognizer = Recognizer()
    _display_queue: queue.Queue = queue.Queue()
    http_server = _start_http_server(camera, recognizer, _display_queue)

    # Graceful shutdown flag
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
    last_recognized_make: str | None = None
    last_hold_check_at: float = 0.0
    gone_since: float | None = None

    logger.info("Startup: running initial recognition scan")
    time.sleep(2)
    _startup_frame = camera.get_frame()
    if _startup_frame is not None:
        try:
            _startup_result = recognizer.recognize(_startup_frame)
        except Exception:
            logger.exception("Startup recognition error")
            _startup_result = None
        if _startup_result is not None:
            _startup_name = _startup_result.matched_vehicle["name"] if _startup_result.matched_vehicle else "unknown"
            logger.info(
                "Startup recognition — vehicle='%s' make='%s' method=%s conf=%.2f",
                _startup_name, _startup_result.make, _startup_result.method_used, _startup_result.confidence,
            )
            _write_result(_startup_result)
            _startup_vehicle  = _startup_result.matched_vehicle
            _startup_greeting = (_startup_vehicle.get("greeting") if _startup_vehicle else None) or f"Welcome, {_startup_name}"
            _startup_badge    = _badge_url(_startup_result.make)
            display.send_recognition(
                make=_startup_result.make or "",
                model=_startup_result.model or "",
                greeting=_startup_greeting,
                badge_url=_startup_badge,
            )
            last_recognition_sent_at = time.monotonic()
            last_recognized_make = _startup_result.make or ""
            last_hold_check_at = 0.0
            gone_since = None
            camera.set_hold_reference(True)
        else:
            logger.info("Startup recognition: no result")
    else:
        logger.warning("Startup recognition: no frame available")

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
            if now_mono - last_state_log_at >= 5.0:
                state = camera.get_motion_state()
                logger.info("Motion state: %s", state.value)
                last_state_log_at = now_mono

            # ── YOLO hold: if we already recognised a car, ignore motion detection ──
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
                        else:
                            if gone_since is None:
                                gone_since = now_mono
                                logger.info("YOLO lost vehicle — starting 5s departure timer")
                            elif now_mono - gone_since >= 5.0:
                                logger.info("Vehicle departed — returning to idle")
                                last_recognized_make = None
                                gone_since = None
                                camera.set_hold_reference(False)
                                _write_idle()
                                display.send_idle()
                time.sleep(0.25)
                continue

            # ── Normal motion-based detection ──
            state = camera.get_motion_state()

            if state != MotionState.PRESENCE:
                if state == MotionState.IDLE:
                    _write_idle()
                    if time.monotonic() - last_recognition_sent_at >= 10.0:
                        display.send_idle()
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
                result = recognizer.recognize(frame)
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
                name = result.matched_vehicle["name"] if result.matched_vehicle else "unknown"
                logger.info(
                    "Recognition complete — vehicle='%s' make='%s' method=%s conf=%.2f",
                    name, result.make, result.method_used, result.confidence,
                )
                _write_result(result)

                vehicle   = result.matched_vehicle
                greeting  = (vehicle.get("greeting") if vehicle else None) or f"Welcome, {name}"
                badge_url = _badge_url(result.make)
                display.send_recognition(
                    make=result.make or "",
                    model=result.model or "",
                    greeting=greeting,
                    badge_url=badge_url,
                )
                last_recognition_sent_at = time.monotonic()
                last_recognized_make = result.make or ""
                last_hold_check_at = 0.0
                gone_since = None
                camera.set_hold_reference(True)

    finally:
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
