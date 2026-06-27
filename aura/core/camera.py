import logging
import threading
import time
from enum import Enum

import cv2
import numpy as np

from aura.config.settings import (
    CAMERA_HEIGHT,
    CAMERA_WIDTH,
    MOTION_THRESHOLD,
    VEHICLE_PRESENCE_SECONDS,
)

logger = logging.getLogger(__name__)

# Fraction of frame area a contour must occupy to count as a large object
_PRESENCE_AREA_RATIO = 0.02


class MotionState(str, Enum):
    IDLE = "IDLE"
    MOTION = "MOTION"
    PRESENCE = "PRESENCE"


class Camera:
    def __init__(self):
        self._lock = threading.Lock()
        self._frame: np.ndarray | None = None
        self._state = MotionState.IDLE
        self._presence_since: float | None = None
        self._force_presence_until: float | None = None
        self._hold_reference: bool = False

        self._cam = None  # set by _camera_loop while running
        self._running = False
        self._thread: threading.Thread | None = None

        self._hflip: bool = False
        self._vflip: bool = False
        self._rotation: int = 0
        self._motion_threshold: float = MOTION_THRESHOLD
        self._restart_requested: bool = False
        # Last-applied Picamera2 controls (Brightness/Contrast/ExposureValue/
        # Sharpness/…). Cached so they survive a camera restart — a fresh
        # Picamera2 starts at libcamera defaults, so without re-applying these
        # every restart would silently revert the settings.
        self._controls: dict = {}

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    def start(self):
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._run, daemon=True, name="camera-loop")
        self._thread.start()
        logger.info("Camera thread started")

    def stop(self):
        self._running = False
        if self._thread:
            self._thread.join(timeout=5)
        logger.info("Camera thread stopped")

    def get_frame(self) -> np.ndarray | None:
        with self._lock:
            return self._frame.copy() if self._frame is not None else None

    def get_motion_state(self) -> MotionState:
        with self._lock:
            return self._state

    def set_hold_reference(self, value: bool) -> None:
        with self._lock:
            self._hold_reference = value
        logger.info("hold_reference set to %s", value)

    @property
    def hold_reference(self) -> bool:
        with self._lock:
            return self._hold_reference

    def force_presence(self, duration: float = 10.0):
        """Override motion detection and hold PRESENCE state for *duration* seconds."""
        with self._lock:
            self._state = MotionState.PRESENCE
            self._force_presence_until = time.monotonic() + duration
        logger.info("force_presence: PRESENCE forced for %.0f s", duration)

    def capture_still(self) -> np.ndarray | None:
        return self.get_frame()

    def apply_controls(self, controls: dict) -> bool:
        """Apply Picamera2 controls to the live camera and remember them.

        The controls are merged into self._controls FIRST, unconditionally, so that:
          • a camera restart (transform change or error recovery) re-applies them in
            _camera_loop instead of silently reverting to libcamera defaults, and
          • controls requested before the camera thread has finished starting
            (self._cam still None — e.g. the startup apply in main()) are not lost;
            they are pushed once the loop comes up.
        Returns True if the controls were pushed to the live camera right now.
        """
        with self._lock:
            self._controls.update(controls)
        cam = self._cam
        if cam is None:
            logger.info("apply_controls: camera not running yet — cached %s for next start", controls)
            return False
        try:
            cam.set_controls(controls)
            logger.info("Camera controls applied: %s", controls)
            return True
        except Exception:
            logger.exception("apply_controls failed")
            return False

    def set_transform(self, hflip: bool, vflip: bool, rotation: int) -> None:
        """Update flip/rotation and restart the camera loop to apply the new transform."""
        with self._lock:
            self._hflip = hflip
            self._vflip = vflip
            self._rotation = rotation
            self._restart_requested = True
        logger.info("Camera transform set: hflip=%s vflip=%s rotation=%d — restart pending", hflip, vflip, rotation)

    def set_motion_threshold(self, threshold: float) -> None:
        with self._lock:
            self._motion_threshold = max(1.0, threshold)
        logger.info("Motion threshold set to %.1f", threshold)

    # ------------------------------------------------------------------
    # Background loop
    # ------------------------------------------------------------------

    def _run(self):
        while self._running:
            try:
                self._camera_loop()
            except Exception:
                logger.exception("Camera error — restarting in 3 s")
                time.sleep(3)

    def _camera_loop(self):
        from picamera2 import Picamera2

        hflip, vflip = self._hflip, self._vflip
        try:
            from libcamera import Transform
            transform = Transform(hflip=int(hflip), vflip=int(vflip))
            config_kwargs = {"transform": transform}
        except Exception:
            config_kwargs = {}

        cam = Picamera2()
        preview_config = cam.create_preview_configuration(
            main={"size": (CAMERA_WIDTH, CAMERA_HEIGHT), "format": "RGB888"},
            **config_kwargs,
        )
        cam.configure(preview_config)
        cam.start()
        self._cam = cam
        logger.info("Picamera2 started (%dx%d) hflip=%s vflip=%s rotation=%d", CAMERA_WIDTH, CAMERA_HEIGHT, hflip, vflip, self._rotation)

        # Re-apply any persisted controls (Brightness/Contrast/ExposureValue/
        # Sharpness/NoiseReductionMode/…) to this fresh Picamera2 instance. A new
        # camera starts at libcamera defaults, so without this every restart — and
        # any settings applied before the camera was ready — would be silently lost.
        with self._lock:
            persisted = dict(self._controls)
        if persisted:
            try:
                cam.set_controls(persisted)
                logger.info("Re-applied persisted camera controls on start: %s", persisted)
            except Exception:
                logger.exception("Failed to re-apply persisted controls on start")

        prev_gray: np.ndarray | None = None
        prev_frame_gray: np.ndarray | None = None
        stable_since: float | None = None
        frame_area = CAMERA_WIDTH * CAMERA_HEIGHT

        try:
            while self._running:
                raw = cam.capture_array()
                bgr = cv2.cvtColor(raw, cv2.COLOR_RGB2BGR)
                rot = self._rotation
                if rot == 90:
                    bgr = cv2.rotate(bgr, cv2.ROTATE_90_CLOCKWISE)
                elif rot == 180:
                    bgr = cv2.rotate(bgr, cv2.ROTATE_180)
                elif rot == 270:
                    bgr = cv2.rotate(bgr, cv2.ROTATE_90_COUNTERCLOCKWISE)

                with self._lock:
                    self._frame = bgr
                    if self._restart_requested:
                        self._restart_requested = False
                        break

                gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
                gray = cv2.GaussianBlur(gray, (21, 21), 0)

                now = time.monotonic()

                if prev_gray is None:
                    prev_gray = gray
                    prev_frame_gray = gray
                    time.sleep(0.1)
                    continue

                # Motion detection against reference frame
                diff = cv2.absdiff(prev_gray, gray)
                _, thresh = cv2.threshold(diff, 25, 255, cv2.THRESH_BINARY)
                thresh = cv2.dilate(thresh, None, iterations=2)

                contours, _ = cv2.findContours(
                    thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
                )

                motion_area = sum(cv2.contourArea(c) for c in contours)
                large_object = any(
                    cv2.contourArea(c) >= frame_area * _PRESENCE_AREA_RATIO
                    for c in contours
                )

                logger.debug("motion_area=%.0f large=%s", motion_area, large_object)

                self._update_state(motion_area, large_object, now)

                # Frame-to-frame stability — update reference when scene settles
                fd = cv2.absdiff(prev_frame_gray, gray)
                _, ft = cv2.threshold(fd, 25, 255, cv2.THRESH_BINARY)
                ft = cv2.dilate(ft, None, iterations=2)
                fc, _ = cv2.findContours(ft, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
                instant_diff = sum(cv2.contourArea(c) for c in fc)

                if instant_diff < 5000:
                    if stable_since is None:
                        stable_since = now
                    if now - stable_since >= 5.0:
                        prev_gray = gray
                        stable_since = None
                        with self._lock:
                            self._hold_reference = False
                        logger.info("Reference frame updated — scene stable for 5 s, releasing hold")
                else:
                    stable_since = None

                prev_frame_gray = gray
                time.sleep(0.25)

        finally:
            self._cam = None
            cam.stop()
            cam.close()
            logger.info("Picamera2 closed")

    def _update_state(self, motion_area: float, large_object: bool, now: float):
        """Determine and apply the new motion state. Must be called from the camera thread."""
        with self._lock:
            # Honour forced presence window
            if self._force_presence_until is not None:
                if now < self._force_presence_until:
                    return
                self._force_presence_until = None

            current_state = self._state
            presence_since = self._presence_since

        # Compute new state
        if motion_area < self._motion_threshold:
            new_state = MotionState.IDLE
            new_presence_since = None
        elif not large_object:
            new_state = MotionState.MOTION
            new_presence_since = None
        else:
            if presence_since is None:
                presence_since = now
            elapsed = now - presence_since
            new_state = MotionState.PRESENCE if elapsed >= VEHICLE_PRESENCE_SECONDS else MotionState.MOTION
            new_presence_since = presence_since

        # Write back under lock
        with self._lock:
            self._presence_since = new_presence_since
            if new_state != current_state:
                logger.info("Motion state: %s → %s", current_state.value, new_state.value)
                self._state = new_state
