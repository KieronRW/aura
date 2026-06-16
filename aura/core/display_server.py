import asyncio
import json
import logging
import threading
import time

import websockets
from websockets.server import WebSocketServerProtocol

logger = logging.getLogger(__name__)

WS_PORT = 8765


class DisplayServer:
    def __init__(self, port: int = WS_PORT):
        self._port = port
        self._clients: set[WebSocketServerProtocol] = set()
        self._loop: asyncio.AbstractEventLoop | None = None
        self._thread: threading.Thread | None = None
        self._ready = threading.Event()
        self._is_idle: bool = True  # suppress log until first non-idle → idle transition

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def start(self):
        """Start the WebSocket server in a background daemon thread."""
        self._thread = threading.Thread(
            target=self._run, daemon=True, name="display-ws"
        )
        self._thread.start()
        self._ready.wait(timeout=5)
        logger.info("DisplayServer ready on ws://localhost:%d", self._port)

    def stop(self):
        if self._loop:
            self._loop.call_soon_threadsafe(self._loop.stop)
        if self._thread:
            self._thread.join(timeout=5)
        logger.info("DisplayServer stopped")

    # ------------------------------------------------------------------
    # Public API  (safe to call from any thread)
    # ------------------------------------------------------------------

    @property
    def client_count(self) -> int:
        return len(self._clients)

    def send_recognition(
        self,
        make: str,
        model: str | None,
        greeting: str,
        badge_url: str | None,
    ):
        payload = json.dumps({
            "state":     "recognition",
            "make":      make,
            "model":     model or "",
            "greeting":  greeting,
            "badge_url": badge_url or "",
        })
        logger.info("Broadcasting recognition — make=%s model=%s", make, model)
        self._is_idle = False
        self._broadcast(payload)

    def send_idle(self):
        payload = json.dumps({"state": "idle"})
        if not self._is_idle:
            logger.info("Broadcasting idle")
            self._is_idle = True
        self._broadcast(payload)

    def send_status_bar(self, data: dict):
        payload = json.dumps({"state": "status_bar", "server_ts": time.time(), **data})
        logger.info("Broadcasting status_bar — show_time=%s show_weather=%s", data.get("show_time"), data.get("show_weather"))
        self._broadcast(payload)

    def send_visitor_pre_arrival(self, name: str, message: str):
        payload = json.dumps({
            "state":        "visitor_pre_arrival",
            "visitor_name": name,
            "message":      message,
        })
        logger.info("Broadcasting visitor pre-arrival — %s", name)
        self._is_idle = False
        self._broadcast(payload)

    def send_visitor_bay_occupied(self, message: str):
        payload = json.dumps({
            "state":   "visitor_bay_occupied",
            "message": message,
        })
        logger.info("Broadcasting visitor bay occupied — %s", message)
        self._is_idle = False
        self._broadcast(payload)

    def send_visitor_mode_ended(self):
        payload = json.dumps({"state": "visitor_mode_ended"})
        logger.info("Broadcasting visitor mode ended")
        self._is_idle = True
        self._broadcast(payload)

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _broadcast(self, message: str):
        """Schedule a broadcast on the server's event loop from any thread."""
        if self._loop is None or not self._loop.is_running():
            logger.warning("DisplayServer loop not running — message dropped")
            return
        future = asyncio.run_coroutine_threadsafe(self._send_all(message), self._loop)
        future.add_done_callback(
            lambda f: logger.warning("DisplayServer _send_all raised: %s", f.exception())
            if not f.cancelled() and f.exception() is not None else None
        )

    async def _send_all(self, message: str):
        if not self._clients:
            logger.debug("No display clients connected — message not sent")
            return
        dead = set()
        for client in self._clients:
            try:
                await client.send(message)
            except websockets.ConnectionClosed:
                dead.add(client)
            except Exception as exc:
                logger.warning("Send failed for client %s: %s", client.remote_address, exc)
                dead.add(client)
        self._clients -= dead

    async def _handler(self, websocket: WebSocketServerProtocol):
        addr = websocket.remote_address
        self._clients.add(websocket)
        logger.info("Display client connected   — %s  (total: %d)", addr, len(self._clients))

        try:
            async for message in websocket:
                # Display clients don't send messages, but log anything received
                logger.debug("Received from %s: %s", addr, message)
        except websockets.ConnectionClosed:
            pass
        finally:
            self._clients.discard(websocket)
            logger.info("Display client disconnected — %s  (total: %d)", addr, len(self._clients))

    def _run(self):
        self._loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self._loop)

        async def serve():
            async with websockets.serve(self._handler, "0.0.0.0", self._port):
                logger.info("WebSocket server listening on port %d", self._port)
                self._ready.set()
                await asyncio.Future()  # run forever

        try:
            self._loop.run_until_complete(serve())
        except RuntimeError as exc:
            # Normal shutdown path: stop() calls loop.stop() which interrupts
            # run_until_complete before the Future completes.
            logger.info("DisplayServer loop stopped: %s", exc)
