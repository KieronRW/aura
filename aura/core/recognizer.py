import logging
import os
import socket
import time
from dataclasses import dataclass, field

import numpy as np

from aura.config.settings import (
    FINGERPRINT_MATCH_THRESHOLD,
    GOOGLE_CREDENTIALS_PATH,
    GOOGLE_VISION_ENABLED,
)
from aura.core import database as db
from aura.core.detector import detect
from aura.core.fingerprint import (
    compare_fingerprints,
    extract_fingerprint,
    json_to_fingerprint,
)

logger = logging.getLogger(__name__)

# Vision results are cached against a fingerprint similarity key for this many seconds
_VISION_CACHE_TTL = 300  # 5 minutes


@dataclass
class RecognitionResult:
    matched_vehicle: dict | None       # full vehicle dict from DB, or None
    make: str | None
    model: str | None
    confidence: float
    method_used: str                   # "fingerprint", "vision", or "yolo"
    badge_path: str | None


@dataclass
class _VisionCacheEntry:
    make: str | None
    model: str | None
    confidence: float
    expires_at: float


class Recognizer:
    def __init__(self):
        self._vision_client = None
        self._vision_cache: dict[int, _VisionCacheEntry] = {}  # vehicle_id → entry

    # ------------------------------------------------------------------
    # Public
    # ------------------------------------------------------------------

    def recognize(self, frame: np.ndarray) -> RecognitionResult | None:
        """
        Full recognition pipeline. Returns None if no vehicle is detected.
        """
        # Step 1 — confirm a vehicle is present via YOLO
        detection = detect(frame)
        if not detection.is_vehicle:
            logger.debug("No vehicle confirmed by detector — skipping recognition")
            return None

        logger.info(
            "Vehicle detected: %s conf=%.2f — starting recognition",
            detection.vehicle_type, detection.confidence,
        )

        # Crop to bounding box for fingerprinting / Vision (tighter feature focus)
        cropped = self._crop(frame, detection.bounding_box)

        # Step 2 — fingerprint matching
        result = self._match_fingerprint(cropped, detection)
        if result:
            db.log_recognition(
                method_used=result.method_used,
                make_detected=result.make,
                confidence=result.confidence,
                vehicle_id=result.matched_vehicle["id"] if result.matched_vehicle else None,
            )
            return result

        # Step 3 — Google Vision fallback
        if GOOGLE_VISION_ENABLED:
            result = self._match_vision(frame, cropped, detection)
            if result:
                db.log_recognition(
                    method_used=result.method_used,
                    make_detected=result.make,
                    confidence=result.confidence,
                    vehicle_id=None,
                )
                return result

        # Step 4 — return YOLO-only result (make/model unknown but vehicle confirmed)
        logger.info("No match found — returning YOLO-only result")
        result = RecognitionResult(
            matched_vehicle=None,
            make=None,
            model=None,
            confidence=detection.confidence,
            method_used="yolo",
            badge_path=None,
        )
        db.log_recognition(
            method_used="yolo",
            make_detected=detection.vehicle_type,
            confidence=detection.confidence,
            vehicle_id=None,
        )
        return result

    # ------------------------------------------------------------------
    # Step 2 — fingerprint
    # ------------------------------------------------------------------

    def _match_fingerprint(self, cropped: np.ndarray, detection) -> RecognitionResult | None:
        vehicles = db.get_all_vehicles(active_only=True)
        if not vehicles:
            logger.debug("No registered vehicles in database")
            return None

        query_fp = extract_fingerprint(cropped)

        best_score = 0.0
        best_vehicle = None

        for vehicle in vehicles:
            raw = vehicle.get("fingerprint_data")
            if not raw:
                continue
            try:
                stored_fp = json_to_fingerprint(raw if isinstance(raw, str) else str(raw))
            except Exception:
                logger.warning("Could not deserialise fingerprint for vehicle id=%s", vehicle["id"])
                continue

            score = compare_fingerprints(query_fp, stored_fp)
            logger.debug("Fingerprint score vs '%s': %.4f", vehicle["name"], score)

            if score > best_score:
                best_score = score
                best_vehicle = vehicle

        if best_vehicle and best_score >= FINGERPRINT_MATCH_THRESHOLD:
            logger.info(
                "Fingerprint match: '%s' score=%.4f", best_vehicle["name"], best_score
            )
            return RecognitionResult(
                matched_vehicle=best_vehicle,
                make=best_vehicle["make"],
                model=best_vehicle["model"],
                confidence=best_score,
                method_used="fingerprint",
                badge_path=best_vehicle.get("badge_path"),
            )

        logger.info(
            "No fingerprint match (best=%.4f threshold=%.2f)",
            best_score, FINGERPRINT_MATCH_THRESHOLD,
        )
        return None

    # ------------------------------------------------------------------
    # Step 3 — Google Vision
    # ------------------------------------------------------------------

    def _match_vision(self, full_frame: np.ndarray, cropped: np.ndarray, detection) -> RecognitionResult | None:
        if not self._is_online():
            logger.warning("Offline — skipping Google Vision")
            return None

        # Check cache using a stable key derived from the cropped image hash
        cache_key = hash(cropped.tobytes())
        cached = self._vision_cache.get(cache_key)
        if cached and time.monotonic() < cached.expires_at:
            logger.info(
                "Vision cache hit — make=%s model=%s conf=%.2f",
                cached.make, cached.model, cached.confidence,
            )
            return RecognitionResult(
                matched_vehicle=None,
                make=cached.make,
                model=cached.model,
                confidence=cached.confidence,
                method_used="vision",
                badge_path=None,
            )

        client = self._get_vision_client()
        if client is None:
            return None

        try:
            import cv2
            from google.cloud import vision

            _, encoded = cv2.imencode(".jpg", cropped)
            image = vision.Image(content=encoded.tobytes())

            web_response = client.web_detection(image=image)
            entities = web_response.web_detection.web_entities

            make, model, confidence = self._parse_vision_entities(entities)

            self._vision_cache[cache_key] = _VisionCacheEntry(
                make=make,
                model=model,
                confidence=confidence,
                expires_at=time.monotonic() + _VISION_CACHE_TTL,
            )

            if make:
                logger.info("Vision result — make=%s model=%s conf=%.2f", make, model, confidence)
                return RecognitionResult(
                    matched_vehicle=None,
                    make=make,
                    model=model,
                    confidence=confidence,
                    method_used="vision",
                    badge_path=None,
                )

            logger.info("Vision returned no usable make/model")
            return None

        except Exception:
            logger.exception("Google Vision API call failed")
            return None

    def _parse_vision_entities(self, entities) -> tuple[str | None, str | None, float]:
        """
        Heuristic: the highest-scoring entity that contains a known car brand is the make.
        The next entity is treated as a model hint.
        """
        car_brands = {
            "toyota", "honda", "ford", "bmw", "mercedes", "volkswagen", "vw",
            "audi", "hyundai", "kia", "nissan", "chevrolet", "chevy", "mazda",
            "subaru", "volvo", "peugeot", "renault", "fiat", "jeep", "ram",
            "dodge", "chrysler", "lexus", "infiniti", "acura", "mitsubishi",
            "suzuki", "isuzu", "land rover", "range rover", "jaguar", "porsche",
            "ferrari", "lamborghini", "maserati", "alfa romeo", "seat", "skoda",
            "opel", "vauxhall", "citroen", "ds", "mini", "bentley", "rolls-royce",
            "tesla", "rivian", "lucid", "genesis", "haval", "chery", "geely",
        }

        sorted_entities = sorted(entities, key=lambda e: e.score, reverse=True)
        make = model = None
        confidence = 0.0

        for entity in sorted_entities:
            desc = entity.description.lower() if entity.description else ""
            for brand in car_brands:
                if brand in desc:
                    make = entity.description
                    confidence = float(entity.score)
                    break
            if make:
                break

        if make:
            # Take the next entity as a potential model label
            for entity in sorted_entities:
                if entity.description and entity.description != make:
                    model = entity.description
                    break

        return make, model, confidence

    def _get_vision_client(self):
        if self._vision_client is not None:
            return self._vision_client
        try:
            os.environ.setdefault("GOOGLE_APPLICATION_CREDENTIALS", GOOGLE_CREDENTIALS_PATH)
            from google.cloud import vision
            self._vision_client = vision.ImageAnnotatorClient()
            logger.info("Google Vision client initialised")
        except Exception:
            logger.exception("Failed to initialise Google Vision client")
            return None
        return self._vision_client

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _crop(frame: np.ndarray, bounding_box: tuple | None) -> np.ndarray:
        if bounding_box is None:
            return frame
        x, y, w, h = bounding_box
        x, y = max(0, x), max(0, y)
        return frame[y:y + h, x:x + w] if w > 0 and h > 0 else frame

    @staticmethod
    def _is_online() -> bool:
        try:
            socket.setdefaulttimeout(2)
            socket.create_connection(("8.8.8.8", 53))
            return True
        except OSError:
            return False
