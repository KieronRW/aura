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

import psutil

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
from aura.core.commands import start_command_listener, trigger_auto_update
from aura.core.discovery import DiscoveryService
from aura.core.camera import Camera, MotionState
from aura.core.cloud import (
    get_cpu_temp,
    get_expected_visitors,
    get_installation_uuid,
    get_property_location,
    get_user_preferences,
    is_connected,
    log_recognition,
    log_unknown_vehicle,
    push_heartbeat,
    save_autolearn_image,
    send_push_notification,
    subscribe_visitor_updates,
    sync_settings,
    sync_vehicles,
    update_departure,
)
from aura.core import display_settings as _display_settings_mod
from aura.core import weather as _weather_mod
from aura.core.display_server import DisplayServer
from aura.core.diagnostics import log_info, log_warning, log_error, log_critical, log_event_sync
from aura.core.enroller import ReferenceImageEnroller
from aura.core.recognizer import Recognizer

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_RECOGNITION_COOLDOWN  = 3        # seconds between recognition attempts
_VEHICLE_SYNC_INTERVAL = 300     # re-sync vehicles from Supabase every 5 minutes
_HEARTBEAT_INTERVAL    = 30      # push device_status heartbeat every 30 seconds
_PRE_ARRIVAL_INTERVAL  = 10      # seconds between cycling pre-arrival visitor messages
_PROPERTY_SYNC_INTERVAL         = 3600   # refresh property location + user prefs every 1 hour
_WEATHER_SYNC_INTERVAL          = 1800   # refresh weather every 30 minutes
_HEALTH_SNAPSHOT_INTERVAL       = 1800   # remote diagnostics health snapshot every 30 minutes
_UPDATE_CHECK_INTERVAL          = 3600   # check git remote for updates every 1 hour
_STATUS_BAR_BROADCAST_INTERVAL  = 10     # push status_bar WS message every 10 seconds
_DISPLAY_SETTINGS_CACHE_TTL     = 30     # re-read display settings from Supabase every 30 seconds
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
        for ext in (".glb", ".png"):
            candidate = _BADGES_DIR / f"{slug}{ext}"
            if candidate.exists():
                return f"{_BADGE_BASE_URL}/{slug}{ext}"

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


def _find_visitor(result, visitors: list[dict]) -> dict | None:
    """Match a recognition result against expected visitors by vehicle_make (case-insensitive)."""
    if not visitors or not result.make:
        return None
    make_lower = result.make.lower()
    for v in visitors:
        v_make = (v.get("vehicle_make") or "").lower().strip()
        if v_make and (v_make in make_lower or make_lower.startswith(v_make)):
            return v
    return None


def _get_active_visitors(visitors: list[dict], installation_uuid: str | None) -> list[dict]:
    """Filter synced visitors to those currently within their time window and matching this installation."""
    now = datetime.now(timezone.utc)
    active = []
    for v in visitors:
        expected_from = v.get("expected_from")
        expected_until = v.get("expected_until")
        if expected_from:
            try:
                from_dt = datetime.fromisoformat(expected_from.replace("Z", "+00:00"))
                if now < from_dt:
                    continue
            except ValueError:
                continue
        if expected_until:
            try:
                until_dt = datetime.fromisoformat(expected_until.replace("Z", "+00:00"))
                if now > until_dt:
                    continue
            except ValueError:
                continue
        installation_ids = v.get("installation_ids")
        if installation_ids and installation_uuid:
            if installation_uuid not in installation_ids:
                continue
        active.append(v)
    return active

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
_STATIC_PORT = 8080
_STATIC_ROOT = Path.home() / "aura"
_TEST_IMAGE_PATH = _STATIC_ROOT / "test_vw_front.jpg"
_PROJECT_ROOT = Path(__file__).resolve().parent


def _make_http_handler(camera: "Camera", recognizer: "Recognizer", display_queue: "queue.Queue", synced_vehicles: list):
    class _Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/test-recognition":
                self._serve_static()
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

        def _serve_static(self):
            # Map request path to a file under the project root.
            # /vendor/* is served from display/vendor/*.
            rel = self.path.lstrip("/").split("?", 1)[0]
            if rel.startswith("vendor/"):
                rel = "display/" + rel
            file_path = (_PROJECT_ROOT / rel).resolve()

            # 404 for missing files or any path escaping the project root.
            if not file_path.is_file() or _PROJECT_ROOT not in file_path.parents:
                self._respond(404, {"error": "not found"})
                return

            content_type = {
                ".html": "text/html",
                ".js": "application/javascript",
                ".glb": "model/gltf-binary",
                ".png": "image/png",
                ".css": "text/css",
            }.get(file_path.suffix.lower(), "application/octet-stream")

            data = file_path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

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


def _start_static_server() -> http.server.HTTPServer:
    """Serve ~/aura/ as a static file root on port 8080.

    /display/index.html  → ~/aura/display/index.html
    /assets/badges/*.png → ~/aura/assets/badges/*.png
    """
    root = str(_STATIC_ROOT)

    class _StaticHandler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=root, **kwargs)

        def log_message(self, fmt, *args):
            logger.debug("HTTP static: " + fmt, *args)

    server = http.server.HTTPServer(("", _STATIC_PORT), _StaticHandler)
    t = threading.Thread(target=server.serve_forever, daemon=True, name="http-static")
    t.start()
    logger.info("Static file server on http://localhost:%d/ (root: %s)", _STATIC_PORT, _STATIC_ROOT)
    return server

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    _print_banner()
    logger.info("AURA v%s starting up", _VERSION)

    from aura.core.update_healthcheck import check_and_rollback_if_needed
    check_and_rollback_if_needed()

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
        "update_available":            False,
        "synced_vehicles":             [],
        "recent_events":               [],
        "trigger_recognition_cb":      None,
        "force_idle_cb":               None,
        "force_recognition_cb":        None,
        "force_status_bar_cb":         None,
        "installation_key":            _installation_key,
        "name":                        socket.gethostname(),
        "software_version":            _VERSION,
    }
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
    _state["display_server"] = display
    api.init(_state)

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
    except Exception as e:
        logger.exception("Failed to start camera — aborting")
        log_critical('camera', 'Camera failed to initialise', {'error': str(e)})
        sys.exit(1)

    _state["camera_ok"] = True
    _state["camera"] = camera
    _state["trigger_recognition_cb"] = camera.force_presence

    _synced_vehicles = sync_vehicles()
    _synced_visitors = get_expected_visitors()
    _synced_settings = sync_settings()
    _installation_uuid = get_installation_uuid()
    logger.info(
        "Supabase sync: %d vehicles, %d visitors, %d settings, uuid=%s",
        len(_synced_vehicles), len(_synced_visitors), len(_synced_settings), _installation_uuid,
    )
    _state["supabase_ok"] = is_connected()
    _state["synced_vehicles"] = _synced_vehicles

    log_info('startup', 'Aura service started', {
        'software_version': _VERSION,
        'installation_id': _installation_uuid,
    })
    if not _state["supabase_ok"]:
        log_error('network', 'Supabase not connected at startup', {'installation_id': _installation_key})

    # Realtime subscription: instant visitor refresh on any UPDATE from the app
    _visitors_stale = threading.Event()
    if _installation_uuid:
        subscribe_visitor_updates(
            _installation_uuid,
            lambda: _visitors_stale.set(),
        )
        start_command_listener(_installation_uuid)

    # Apply persisted camera settings to the live camera
    try:
        from aura.core.camera_settings import apply_settings as _apply_cam_settings, get_settings as _get_cam_settings
        _cam_settings = _get_cam_settings()
        _apply_cam_settings(_cam_settings, camera)
        logger.info("Camera settings applied from Supabase: %s", _cam_settings)
    except Exception:
        logger.exception("Failed to apply camera settings on startup")

    def _resync_vehicles() -> None:
        nonlocal _synced_vehicles
        fresh = sync_vehicles()
        if fresh:
            _synced_vehicles = fresh
            _state["synced_vehicles"] = _synced_vehicles
            logger.info(
                "Enroller triggered vehicle re-sync: %d vehicles loaded",
                len(_synced_vehicles),
            )

    enroller = None
    try:
        enroller = ReferenceImageEnroller(on_vehicle_updated=_resync_vehicles)
        enroller.start()
    except Exception:
        logger.exception("Failed to initialise enroller")

    recognizer = Recognizer()
    _display_queue: queue.Queue = queue.Queue()

    static_server = _start_static_server()
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
    autolearn_last_at: dict[int, float] = {}  # vehicle_id → monotonic time of last auto-learn
    last_pre_arrival_at: float = 0.0
    pre_arrival_index: int = 0
    _in_visitor_mode: bool = False

    # ── Property location / weather / preferences / status-bar cache ─────
    # Negative offsets ensure the first loop tick fires the sync regardless of system uptime.
    # (time.monotonic() starts from boot, so 0.0 would require > 1-hour uptime before firing.)
    last_property_sync_at: float = -_PROPERTY_SYNC_INTERVAL
    last_weather_sync_at: float = -_WEATHER_SYNC_INTERVAL
    last_health_snapshot_at: float = -_HEALTH_SNAPSHOT_INTERVAL
    last_update_check_at: float = -_UPDATE_CHECK_INTERVAL
    _auto_update_triggered: bool = False
    last_display_settings_at: float = 0.0
    last_status_bar_at: float = 0.0
    _cached_lat: float | None = None
    _cached_lon: float | None = None
    _cached_user_id: str | None = None
    _cached_prefs: dict = {"units": "metric", "time_format": "24h"}
    _cached_weather_data: dict | None = None
    _cached_display_settings: dict = {"show_time": False, "show_weather": False}

    def _force_status_bar() -> None:
        """Broadcast a status_bar WS message immediately, refreshing display settings first."""
        nonlocal _cached_display_settings
        _cached_display_settings = _display_settings_mod.get_settings()
        s = _cached_display_settings
        show_time = bool(s.get("show_time"))
        show_weather = bool(s.get("show_weather"))
        temp_c = _cached_weather_data.get("temp_c") if _cached_weather_data else None
        wcode = _cached_weather_data.get("weather_code") if _cached_weather_data else None
        display.send_status_bar({
            "show_time": show_time,
            "show_weather": show_weather,
            "time_format": _cached_prefs.get("time_format", "24h"),
            "units": _cached_prefs.get("units", "metric"),
            "temp_c": temp_c,
            "weather_code": wcode,
            "status_bar_scale": _cached_display_settings.get("status_bar_scale", 100),
        })

    _state["force_status_bar_cb"] = _force_status_bar

    def _push_settings_update() -> None:
        """Broadcast current display settings to the display immediately (live update).

        Called from POST /display/settings after a save so badge scale / spin / status-
        bar scale changes apply to the running scene without a new recognition event.
        """
        nonlocal _cached_display_settings
        _cached_display_settings = _display_settings_mod.get_settings()
        s = _cached_display_settings
        display.send_settings_update({
            "badge_scale": s.get("badge_scale", 100),
            "badge_spin_period": s.get("badge_spin_period", 20),
            "badge_spin_direction": s.get("badge_spin_direction", 1),
            "status_bar_scale": s.get("status_bar_scale", 100),
        })

    _state["push_settings_update_cb"] = _push_settings_update

    def _badge_settings() -> dict:
        """Current 3D-badge settings for the recognition payload (read from cache)."""
        s = _cached_display_settings
        return {
            "badge_scale": s.get("badge_scale", 100),
            "badge_spin_period": s.get("badge_spin_period", 20),
            "badge_spin_direction": s.get("badge_spin_direction", 1),
        }

    # Populate display settings so the startup recognition carries current badge values.
    _cached_display_settings = _display_settings_mod.get_settings()

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
                    image_frame=startup_frame,
                )
                display.send_recognition(make=startup_result.make or "", model=startup_result.model or "", greeting=greeting, badge_url=badge_url, **_badge_settings())
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
                    display.send_recognition(make=cmd[1], model=cmd[2], greeting=cmd[3], badge_url=cmd[4], **_badge_settings())
                    last_recognition_sent_at = time.monotonic()
                elif cmd[0] == "idle":
                    if time.monotonic() - last_recognition_sent_at >= 10.0:
                        display.send_idle()

            now_mono = time.monotonic()

            # ── Realtime visitor refresh (instant, triggered by app changes) ──
            if _visitors_stale.is_set():
                _visitors_stale.clear()
                _synced_visitors = get_expected_visitors()
                logger.info("Realtime: visitor update applied — %d visitors", len(_synced_visitors))

            # ── Periodic vehicle + visitor sync (every 5 minutes) ────────────
            if now_mono - last_vehicle_sync_at >= _VEHICLE_SYNC_INTERVAL:
                last_vehicle_sync_at = now_mono
                fresh = sync_vehicles()
                if fresh:
                    _synced_vehicles = fresh
                    _state["synced_vehicles"] = _synced_vehicles
                    logger.info("Vehicle sync: %d vehicles refreshed", len(_synced_vehicles))
                else:
                    logger.warning("Vehicle sync returned empty — retaining previous data")
                _synced_visitors = get_expected_visitors()
                logger.info("Visitor sync: %d expected visitors", len(_synced_visitors))

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
                    update_available=_state["update_available"],
                )

            # ── Health snapshot (every 30 min) ────────────────────────────────
            # Reads psutil fresh here — NOT during the heartbeat tick — to avoid
            # calling cpu_percent(interval=None) twice in quick succession, which
            # would make push_heartbeat measure over a microsecond window and
            # report ~100% CPU erroneously.
            if now_mono - last_health_snapshot_at >= _HEALTH_SNAPSHOT_INTERVAL:
                last_health_snapshot_at = now_mono
                log_info('health_snapshot', 'Periodic health check', {
                    'cpu_percent': psutil.cpu_percent(interval=None),
                    'memory_percent': psutil.virtual_memory().percent,
                    'disk_percent': psutil.disk_usage('/').percent,
                    'cpu_temp_c': get_cpu_temp(),
                    'uptime_seconds': int(now_mono - _start_time),
                    'display_clients': _state['display_clients'],
                    'camera_ok': _state['camera_ok'],
                })

            # ── Property location + user prefs (every 1 hour) ────────────────
            if now_mono - last_property_sync_at >= _PROPERTY_SYNC_INTERVAL:
                last_property_sync_at = now_mono
                if _installation_uuid:
                    logger.info("Property sync: fetching location for uuid=%s", _installation_uuid)
                    try:
                        _cached_lat, _cached_lon, _cached_user_id = get_property_location(_installation_uuid)
                        if _cached_user_id:
                            _cached_prefs = get_user_preferences(_cached_user_id)
                        logger.info(
                            "Property sync complete: lat=%s lon=%s user_id=%s prefs=%s",
                            _cached_lat, _cached_lon, _cached_user_id, _cached_prefs,
                        )
                        if _cached_lat is None or _cached_lon is None:
                            logger.warning(
                                "Property sync: no location — verify installations.property_id is set for uuid=%s",
                                _installation_uuid,
                            )
                    except Exception:
                        logger.exception("Property sync failed unexpectedly")
                else:
                    logger.warning(
                        "Property sync skipped: installation UUID is None — check INSTALLATION_ID env var and Supabase"
                    )

            # ── Weather refresh (every 30 minutes) ───────────────────────────
            if now_mono - last_weather_sync_at >= _WEATHER_SYNC_INTERVAL:
                last_weather_sync_at = now_mono
                if _cached_lat is not None and _cached_lon is not None:
                    logger.info("Weather sync: fetching for lat=%.4f lon=%.4f", _cached_lat, _cached_lon)
                    try:
                        w = _weather_mod.get_weather(_cached_lat, _cached_lon)
                        if w is not None:
                            _cached_weather_data = w
                            logger.info("Weather updated: %.1f°C code=%d", w["temp_c"], w["weather_code"])
                        else:
                            logger.warning("Weather sync: get_weather returned None")
                            log_warning('general', 'Weather fetch failed', {'lat': _cached_lat, 'lon': _cached_lon})
                    except Exception as e:
                        logger.exception("Weather sync failed unexpectedly")
                        log_warning('general', 'Weather fetch failed', {'lat': _cached_lat, 'lon': _cached_lon, 'error': str(e)})
                else:
                    logger.debug("Weather sync skipped: no location cached yet (lat=%s lon=%s)", _cached_lat, _cached_lon)

            # ── Update check (every hour, runs in background thread) ─────────
            if now_mono - last_update_check_at >= _UPDATE_CHECK_INTERVAL:
                last_update_check_at = now_mono

                def _run_update_check(s=_state):
                    from aura.core import update_check as _uc
                    try:
                        available = _uc.is_update_available()
                        if available and not s["update_available"]:
                            remote_ver = _uc.get_remote_version()
                            log_info('update', 'Update available', {'remote_version': remote_ver})
                        s["update_available"] = available
                    except Exception as exc:
                        logger.warning("Update check failed: %s", exc)

                threading.Thread(
                    target=_run_update_check, daemon=True, name="update-check"
                ).start()

            # ── Auto-update trigger (2–4 AM, once per available cycle) ────────
            if _state["update_available"] and not _auto_update_triggered:
                _now_local = datetime.now()
                _auto_enabled = str(_synced_settings.get("auto_update", "true")).lower() in (
                    "true", "1", "yes"
                )
                if _auto_enabled and 2 <= _now_local.hour < 4:
                    trigger_auto_update()
                    log_info('update', 'Auto-update triggered', {'hour': _now_local.hour})
                    _auto_update_triggered = True
            elif not _state["update_available"]:
                _auto_update_triggered = False

            # ── Display settings cache refresh (every 30 s) ───────────────────
            if now_mono - last_display_settings_at >= _DISPLAY_SETTINGS_CACHE_TTL:
                last_display_settings_at = now_mono
                _cached_display_settings = _display_settings_mod.get_settings()

            # ── Independent status bar broadcast (every 10 s) ─────────────────
            if now_mono - last_status_bar_at >= _STATUS_BAR_BROADCAST_INTERVAL:
                last_status_bar_at = now_mono
                show_time = bool(_cached_display_settings.get("show_time"))
                show_weather = bool(_cached_display_settings.get("show_weather"))
                temp_c = _cached_weather_data.get("temp_c") if _cached_weather_data else None
                wcode = _cached_weather_data.get("weather_code") if _cached_weather_data else None
                logger.info("STATUS BAR BROADCAST: show_time=%s show_weather=%s temp_c=%s", show_time, show_weather, temp_c)
                display.send_status_bar({
                    "show_time": show_time,
                    "show_weather": show_weather,
                    "time_format": _cached_prefs.get("time_format", "24h"),
                    "units": _cached_prefs.get("units", "metric"),
                    "temp_c": temp_c,
                    "weather_code": wcode,
                    "status_bar_scale": _cached_display_settings.get("status_bar_scale", 100),
                })

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
                                display.send_recognition(make=last_recognized_make, model="", greeting="", badge_url=badge_url, **_badge_settings())
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
                    if now_mono - last_recognition_sent_at >= 10.0:
                        active_pre = _get_active_visitors(_synced_visitors, _installation_uuid)
                        if active_pre:
                            _in_visitor_mode = True
                            if now_mono - last_pre_arrival_at >= _PRE_ARRIVAL_INTERVAL:
                                last_pre_arrival_at = now_mono
                                v = active_pre[pre_arrival_index % len(active_pre)]
                                pre_arrival_index += 1
                                vname = v.get("name") or "Visitor"
                                msg = v.get("pre_arrival_message") or f"Welcome {vname}, please park here"
                                display.send_visitor_pre_arrival(vname, msg)
                        else:
                            if _in_visitor_mode:
                                _in_visitor_mode = False
                                display.send_visitor_mode_ended()
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

            # ── Visitor mode: bypass fingerprint matching when visitors are active ──
            active_visitors_now = _get_active_visitors(_synced_visitors, _installation_uuid)
            if active_visitors_now:
                logger.info(
                    "Visitor mode: %d active visitor(s) — running YOLO+Vision only",
                    len(active_visitors_now),
                )
                try:
                    result = recognizer.recognize(frame, vehicles=[], settings=_synced_settings)
                except Exception:
                    logger.exception("Visitor mode recognition error")
                    time.sleep(0.25)
                    continue

                if result is None:
                    logger.info("Visitor mode: no vehicle confirmed by detector")
                    _write_idle()
                    if time.monotonic() - last_recognition_sent_at >= 10.0:
                        display.send_idle()
                else:
                    visitor = _find_visitor(result, active_visitors_now)
                    if visitor:
                        name = visitor.get("name") or "Visitor"
                        greeting = (
                            visitor.get("arrival_message")
                            or visitor.get("greeting")
                            or f"Welcome, {name}"
                        )
                        visitor_id = visitor.get("id")
                        needs_review = False
                    else:
                        bay_visitor = active_visitors_now[0]
                        bay_name = bay_visitor.get("name") or "Visitor"
                        name = "Visitor"
                        greeting = (
                            bay_visitor.get("bay_occupied_message")
                            or f"This bay is reserved for {bay_name}"
                        )
                        visitor_id = None
                        needs_review = True

                    logger.info(
                        "Visitor mode result — name='%s' make='%s' method=%s conf=%.2f",
                        visitor.get("name") if visitor else "bay_occupied",
                        result.make, result.method_used, result.confidence,
                    )
                    _write_result(result, None)
                    badge_url = _badge_url(result.make)

                    if last_event_id is None or (result.make and result.make != last_recognized_make):
                        event = log_recognition(
                            result.make or "", result.model or "", result.confidence,
                            result.method_used, None,
                            image_frame=frame,
                            visitor_id=visitor_id,
                            needs_review=needs_review,
                        )
                        last_event_id = event["id"] if event else None
                        log_info('recognition', f'Vehicle recognised: {result.make} {result.model}', {
                            'make': result.make,
                            'model': result.model,
                            'confidence': result.confidence,
                            'method': result.method_used,
                        })
                        if visitor:
                            send_push_notification(
                                f"{name} has arrived",
                                f"{result.make or 'Vehicle'} detected",
                            )
                        elif needs_review:
                            log_unknown_vehicle(result.make, result.model, result.confidence, image_frame=frame)
                            send_push_notification(
                                "Unknown visitor detected",
                                f"{result.make or 'Vehicle'} at gate",
                            )

                    if visitor:
                        display.send_recognition(
                            make=result.make or "",
                            model=result.model or "",
                            greeting=greeting,
                            badge_url=badge_url,
                            **_badge_settings(),
                        )
                    else:
                        display.send_visitor_bay_occupied(greeting)
                    last_recognition_sent_at = time.monotonic()
                    last_recognized_make = result.make or ""
                    last_hold_check_at = 0.0
                    gone_since = None
                    camera.set_hold_reference(True)

                    _state["current_state"] = "detected"
                    _state["vehicle_present"] = True
                    _state["last_recognized_make"] = result.make
                    _state["last_recognized_owner"] = name if visitor else None
                    _state["last_recognition_confidence"] = result.confidence
                    _state["recent_events"] = ([{
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                        "make": result.make,
                        "model": result.model,
                        "confidence": result.confidence,
                        "method_used": result.method_used,
                        "owner_name": None,
                    }] + _state["recent_events"])[:20]

                time.sleep(0.25)
                continue

            # ── Normal mode: full recognition pipeline ───────────────────────────
            logger.info("Running recognition pipeline")
            try:
                result = recognizer.recognize(frame, _synced_vehicles, settings=_synced_settings)
            except Exception as e:
                logger.exception("Recognition pipeline error")
                log_warning('recognition', 'Recognition failed or low confidence', {'error': str(e)})
                time.sleep(0.25)
                continue

            if result is None:
                logger.info("Recognizer returned no result")
                _write_idle()
                if time.monotonic() - last_recognition_sent_at >= 10.0:
                    display.send_idle()
            else:
                vehicle = result.matched_vehicle or _find_vehicle_by_make(result.make, _synced_vehicles)
                visitor: dict | None = None
                visitor_id = None
                needs_review = False

                bay_occupied_greeting: str | None = None
                if not vehicle:
                    active_visitors_now = _get_active_visitors(_synced_visitors, _installation_uuid)
                    visitor = _find_visitor(result, active_visitors_now)
                    if visitor:
                        visitor_id = visitor.get("id")
                    elif active_visitors_now:
                        bay_visitor = active_visitors_now[0]
                        bay_name = bay_visitor.get("name") or "Visitor"
                        bay_occupied_greeting = (
                            bay_visitor.get("bay_occupied_message")
                            or f"This bay is reserved for {bay_name}"
                        )
                        needs_review = True
                    else:
                        needs_review = True

                if vehicle:
                    name = vehicle["owner_name"]
                    greeting = vehicle.get("owner_greeting") or f"Welcome, {name}"
                elif visitor:
                    name = visitor.get("name") or "Visitor"
                    greeting = visitor.get("arrival_message") or visitor.get("greeting") or f"Welcome, {name}"
                elif bay_occupied_greeting:
                    name = "Visitor"
                    greeting = bay_occupied_greeting
                else:
                    name = "Visitor"
                    greeting = "Welcome Visitor"

                logger.info(
                    "Recognition complete — vehicle='%s' make='%s' method=%s conf=%.2f",
                    name, result.make, result.method_used, result.confidence,
                )
                _write_result(result, vehicle)

                badge_url = _badge_url(result.make)

                # Only log a new event if this is a new vehicle arrival
                if last_event_id is None or (result.make and result.make != last_recognized_make):
                    event = log_recognition(
                        result.make or "", result.model or "", result.confidence,
                        result.method_used, vehicle["id"] if vehicle else None,
                        image_frame=frame,
                        visitor_id=visitor_id,
                        needs_review=needs_review,
                    )
                    last_event_id = event["id"] if event else None
                    log_info('recognition', f'Vehicle recognised: {result.make} {result.model}', {
                        'make': result.make,
                        'model': result.model,
                        'confidence': result.confidence,
                        'method': result.method_used,
                    })
                    if visitor:
                        send_push_notification(
                            f"{name} has arrived",
                            f"{result.make or 'Vehicle'} detected",
                        )
                    elif needs_review:
                        log_unknown_vehicle(result.make, result.model, result.confidence, image_frame=frame)
                        send_push_notification(
                            "Unknown visitor detected",
                            f"{result.make or 'Vehicle'} at gate",
                        )

                # Auto-learn: capture a new reference image when Vision matched a known
                # vehicle but the fingerprint came close without crossing the threshold.
                _vehicle_id = vehicle["id"] if vehicle else None
                from aura.core.recognition_settings import get_settings_cached as _get_rs
                _rs = _get_rs()
                if (
                    result.method_used == "vision"
                    and _vehicle_id is not None
                    and result.confidence >= _rs["vision_confidence_gate"]
                    and _rs["auto_learn_min"] <= result.best_fp_score <= _rs["auto_learn_max"]
                    and (vehicle.get("reference_image_count") or 0) < 10
                    and time.monotonic() - autolearn_last_at.get(_vehicle_id, 0.0) >= 3600.0
                ):
                    if save_autolearn_image(_vehicle_id, frame):
                        autolearn_last_at[_vehicle_id] = time.monotonic()
                        logger.info(
                            "Auto-learn: saved frame for vehicle_id=%s"
                            " (fp_score=%.4f, vision_conf=%.2f)",
                            _vehicle_id, result.best_fp_score, result.confidence,
                        )

                display.send_recognition(
                    make=result.make or "",
                    model=result.model or "",
                    greeting=greeting,
                    badge_url=badge_url,
                    **_badge_settings(),
                )
                last_recognition_sent_at = time.monotonic()
                last_recognized_make = result.make or ""
                last_hold_check_at = 0.0  # trigger immediate YOLO hold check on next iteration
                gone_since = None
                camera.set_hold_reference(True)

                _state["current_state"] = "recognized" if vehicle else "detected"
                _state["vehicle_present"] = True
                _state["last_recognized_make"] = result.make
                _state["last_recognized_owner"] = name if (vehicle or visitor) else None
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
        log_event_sync('info', 'shutdown', 'Aura service stopping')
        _discovery.stop()
        if enroller is not None:
            enroller.stop()
        static_server.shutdown()
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
