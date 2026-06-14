import hashlib
import logging
import os
import socket
import time
from dataclasses import dataclass

import numpy as np

from aura.config.settings import (
    FINGERPRINT_MATCH_THRESHOLD,
    GOOGLE_CREDENTIALS_PATH,
    GOOGLE_VISION_ENABLED,
)
from aura.core.detector import detect
from aura.core.fingerprint import (
    compare_fingerprints,
    extract_fingerprint,
    json_to_fingerprint,
)
from aura.core.quality import check_quality

logger = logging.getLogger(__name__)

# Vision results are cached against a stable image hash for this many seconds
_VISION_CACHE_TTL = 300  # 5 minutes

# Fingerprint threshold used when there is no internet connection.
# Loaded from recognition_settings (cached, 60s TTL) so it can be tuned via the app.
def _offline_fp_threshold() -> float:
    try:
        from aura.core.recognition_settings import get_settings_cached
        return get_settings_cached()["offline_fp_threshold"]
    except Exception:
        return 0.60  # safe fallback if settings unavailable


@dataclass
class RecognitionResult:
    matched_vehicle: dict | None       # full vehicle dict from Supabase, or None
    make: str | None
    model: str | None
    confidence: float
    method_used: str                   # "fingerprint", "vision", or "unknown"
    confidence_tier: str               # "high", "medium", "low"
    badge_path: str | None
    best_fp_score: float = 0.0         # highest fingerprint score seen before Vision fallback


@dataclass
class _VisionCacheEntry:
    make: str | None
    model: str | None
    confidence: float
    expires_at: float


class Recognizer:
    def __init__(self):
        self._vision_client = None
        self._vision_cache: dict[str, _VisionCacheEntry] = {}
        self._last_fp_score: float = 0.0  # best fingerprint score from most recent recognize() call  # md5 hex → entry

    # ------------------------------------------------------------------
    # Public
    # ------------------------------------------------------------------

    def recognize(self, frame: np.ndarray, vehicles: list[dict] | None = None, *, settings: dict | None = None) -> RecognitionResult | None:
        """
        Full recognition pipeline. Returns None if no vehicle is detected.
        Recognition events are logged by the caller via cloud.log_recognition().
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

        # Step 1b — quality gate on the cropped frame
        if settings is not None:
            passed, score = check_quality(cropped, settings)
            if not passed:
                logger.debug("Quality check failed (score=%.2f) — skipping recognition", score)
                return None

        # Step 2 — fingerprint matching against synced vehicles
        online = self._is_online()
        if not online:
            logger.info(
                "Offline mode: using reduced fingerprint threshold (%.2f)",
                _offline_fp_threshold(),
            )
        fp_threshold = FINGERPRINT_MATCH_THRESHOLD if online else _offline_fp_threshold()

        self._last_fp_score = 0.0
        result = self._match_fingerprint(cropped, detection, vehicles or [], threshold=fp_threshold)
        if result:
            return result

        # Step 3 — Google Vision fallback (skipped when offline)
        if GOOGLE_VISION_ENABLED and online:
            result = self._match_vision(frame, cropped, detection)
            if result:
                result.best_fp_score = self._last_fp_score
                logger.debug(
                    "Vision result returning — best_fp_score=%.4f", result.best_fp_score
                )
                return result

        # Step 4 — vehicle confirmed by YOLO but make/model unknown
        logger.info("No match found — returning unknown vehicle result")
        return RecognitionResult(
            matched_vehicle=None,
            make=None,
            model=None,
            confidence=detection.confidence,
            method_used="unknown",
            confidence_tier="low",
            badge_path=None,
        )

    # ------------------------------------------------------------------
    # Step 2 — fingerprint
    # ------------------------------------------------------------------

    def _match_fingerprint(
        self,
        cropped: np.ndarray,
        detection,
        vehicles: list[dict],
        *,
        threshold: float = FINGERPRINT_MATCH_THRESHOLD,
    ) -> RecognitionResult | None:
        if not vehicles:
            logger.debug("No registered vehicles available")
            return None

        query_fp = extract_fingerprint(cropped)

        best_score = 0.0
        best_vehicle = None

        for vehicle in vehicles:
            ref_fps = vehicle.get("reference_fingerprints") or []
            if not ref_fps:
                continue

            vehicle_best = 0.0
            for raw in ref_fps:
                try:
                    stored_fp = json_to_fingerprint(raw if isinstance(raw, str) else str(raw))
                    score = compare_fingerprints(query_fp, stored_fp)
                    if score > vehicle_best:
                        vehicle_best = score
                except Exception:
                    logger.warning(
                        "Could not deserialise reference fingerprint for vehicle id=%s",
                        vehicle["id"],
                    )

            logger.debug(
                "Fingerprint best score vs '%s' (%d refs): %.4f",
                vehicle["owner_name"], len(ref_fps), vehicle_best,
            )
            if vehicle_best > best_score:
                best_score = vehicle_best
                best_vehicle = vehicle

        if best_vehicle and best_score >= threshold:
            logger.info(
                "Fingerprint match: '%s' score=%.4f", best_vehicle["owner_name"], best_score
            )
            return RecognitionResult(
                matched_vehicle=best_vehicle,
                make=best_vehicle["make"],
                model=best_vehicle["model"],
                confidence=best_score,
                method_used="fingerprint",
                confidence_tier="high",
                badge_path=best_vehicle.get("custom_badge_path"),
            )

        logger.info(
            "No fingerprint match (best=%.4f threshold=%.2f)",
            best_score, threshold,
        )
        self._last_fp_score = best_score
        return None

    # ------------------------------------------------------------------
    # Step 3 — Google Vision
    # ------------------------------------------------------------------

    def _match_vision(self, full_frame: np.ndarray, cropped: np.ndarray, detection) -> RecognitionResult | None:
        if not self._is_online():
            logger.warning("Offline — skipping Google Vision")
            return None

        # Stable, process-safe cache key using MD5 of the cropped image bytes
        cache_key = hashlib.md5(cropped.tobytes(), usedforsecurity=False).hexdigest()
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
                confidence_tier="medium",
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
                    confidence_tier="medium",
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
        The next distinct entity that is not a generic vehicle term or a car brand is the model.
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

        _GENERIC_VEHICLE_TERMS = {
            "car", "vehicle", "motor vehicle", "automobile", "sedan", "hatchback",
            "hot hatch", "suv", "sport utility vehicle", "compact sport utility vehicle",
            "subcompact car", "compact car", "mid-size car", "full-size car",
            "luxury vehicle", "family car", "city car", "crossover", "wagon",
            "coupe", "convertible", "pickup truck", "truck", "minivan", "van",
            "wheel", "tire", "bumper", "headlamp", "grille", "automotive design",
            "automotive exterior", "automotive lighting", "performance car",
            "personal luxury car", "sports car", "muscle car",
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
            for entity in sorted_entities:
                if not entity.description or entity.description == make:
                    continue
                desc_lower = entity.description.lower()
                if desc_lower in _GENERIC_VEHICLE_TERMS:
                    continue
                if any(brand in desc_lower for brand in car_brands):
                    continue
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
