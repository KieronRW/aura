import asyncio
import json
import logging
import threading

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
        self._broadcast(payload)

    def send_idle(self):
        payload = json.dumps({"state": "idle"})
        logger.info("Broadcasting idle")
        self._broadcast(payload)

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _broadcast(self, message: str):
        """Schedule a broadcast on the server's event loop from any thread."""
        if self._loop is None or not self._loop.is_running():
            logger.warning("DisplayServer loop not running — message dropped")
            return
        asyncio.run_coroutine_threadsafe(self._send_all(message), self._loop)

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

        self._loop.run_until_complete(serve())
