import hashlib
import logging
import os
import socket
import threading
import time
from dataclasses import dataclass

import numpy as np

from aura.config.settings import (
    GOOGLE_CREDENTIALS_PATH,
    GOOGLE_VISION_ENABLED,
)
from aura.core.detector import detect
from aura.core.fingerprint import (
    build_prototype,
    extract_fingerprint,
    fingerprint_to_json,
    json_to_fingerprint,
)
from aura.core.quality import check_quality

logger = logging.getLogger(__name__)

# Vision results are cached against a stable image hash for this many seconds
_VISION_CACHE_TTL = 300  # 5 minutes

# Auto-learn: once per vehicle per hour to avoid spamming similar frames
_AUTO_LEARN_COOLDOWN = 3600.0  # seconds


def _load_fp_settings() -> dict:
    """Return recognition settings with safe fallbacks (cached at 60s TTL by recognition_settings)."""
    try:
        from aura.core.recognition_settings import get_settings_cached
        return get_settings_cached()
    except Exception:
        return {"fp_match_floor": 0.55, "fp_match_margin": 0.08, "offline_fp_threshold": 0.60}


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
        self._last_fp_score: float = 0.0  # best fingerprint score from most recent recognize() call
        # Prototype cache: {vehicle_id: {"prototype": np.ndarray, "count": int}}
        # Invalidated automatically when reference_fingerprint count changes.
        self._prototype_cache: dict = {}
        # Cooldown tracker for auto-learn (vehicle_id → monotonic time of last trigger)
        self._auto_learn_cooldown: dict = {}

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

        # Step 2 — prototype + k-NN fingerprint matching
        online = self._is_online()
        _rs = _load_fp_settings()
        if online:
            fp_floor  = _rs.get("fp_match_floor", 0.55)
        else:
            fp_floor = _rs.get("offline_fp_threshold", 0.60)
            logger.info("Offline mode: using fingerprint floor=%.2f (offline_fp_threshold)", fp_floor)
        fp_margin = _rs.get("fp_match_margin", 0.08)

        self._last_fp_score = 0.0
        result = self._match_fingerprint(cropped, detection, vehicles or [], floor=fp_floor, margin=fp_margin)
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
        floor: float = 0.55,
        margin: float = 0.08,
    ) -> RecognitionResult | None:
        """
        Prototype + margin classifier.

        For each enrolled vehicle, a single prototype vector is built by averaging
        all its reference embeddings (L2-normalised). The live frame embedding is
        then compared to every prototype via cosine similarity.

        A match is declared only when BOTH conditions hold:
          1. best_score >= floor   (absolute quality floor)
          2. best_score - second_best >= margin   (relative confidence gap)

        Condition 2 is skipped when only one vehicle is enrolled (no competition).
        This "margin" criterion is the key improvement over single-threshold matching:
        it rejects ambiguous frames where two vehicles score similarly, while accepting
        clear winners even at moderate absolute scores.
        """
        if not vehicles:
            logger.debug("No registered vehicles available")
            return None

        query_fp = extract_fingerprint(cropped)

        # Score live embedding against each vehicle's prototype
        scores: list[tuple[float, dict]] = []
        for vehicle in vehicles:
            proto = self._get_prototype(vehicle)
            if proto is None:
                continue
            if query_fp.embedding.shape != proto.shape:
                logger.warning(
                    "Embedding dimension mismatch for vehicle %s (%d vs %d) — skipping",
                    vehicle["id"], len(query_fp.embedding), len(proto),
                )
                continue
            score = float(np.dot(query_fp.embedding, proto))
            score = max(0.0, min(1.0, score))
            scores.append((score, vehicle))
            logger.debug(
                "Prototype score vs '%s': %.4f",
                vehicle.get("make", vehicle["id"]), score,
            )

        if not scores:
            logger.info("No vehicle prototypes available — fingerprint skipped")
            return None

        scores.sort(key=lambda x: x[0], reverse=True)
        best_score, best_vehicle = scores[0]

        if len(scores) >= 2:
            second_score, second_vehicle = scores[1]
            actual_margin = best_score - second_score
            second_make = second_vehicle.get("make", "?")
        else:
            second_score = 0.0
            second_vehicle = None
            actual_margin = best_score   # single vehicle: treat full score as the gap
            second_make = "—"

        passes_floor  = best_score >= floor
        passes_margin = len(scores) < 2 or actual_margin >= margin

        if passes_floor and passes_margin:
            # Calibrated confidence: blends absolute score (70%) and normalised margin (30%).
            # A match that barely clears the floor with a tight margin scores lower than
            # one that is far ahead of all alternatives.
            if len(scores) >= 2:
                margin_factor = min(1.0, actual_margin / max(margin, 1e-6))
                confidence = round(min(1.0, 0.7 * best_score + 0.3 * margin_factor), 4)
            else:
                confidence = round(best_score, 4)

            logger.info(
                "Fingerprint match: %s (score=%.3f, margin=%.3f, 2nd=%s@%.3f)",
                best_vehicle.get("make", "?"), best_score, actual_margin,
                second_make, second_score,
            )

            # Auto-learn: store live embedding so prototype improves over time.
            # Rate-limited to once per vehicle per hour to avoid near-duplicate frames.
            now = time.monotonic()
            last_learn = self._auto_learn_cooldown.get(best_vehicle["id"], 0.0)
            if self._is_online() and now - last_learn >= _AUTO_LEARN_COOLDOWN:
                self._auto_learn_cooldown[best_vehicle["id"]] = now
                self._trigger_auto_learn(best_vehicle, query_fp)

            return RecognitionResult(
                matched_vehicle=best_vehicle,
                make=best_vehicle.get("make"),
                model=best_vehicle.get("model"),
                confidence=confidence,
                method_used="fingerprint",
                confidence_tier="high",
                badge_path=best_vehicle.get("custom_badge_path"),
            )

        # Rejection — log the deciding factor
        if not passes_floor:
            logger.info(
                "Fingerprint rejected: best=%s@%.3f margin=%.3f below floor %.2f",
                best_vehicle.get("make", "?"), best_score, actual_margin, floor,
            )
        else:
            logger.info(
                "Fingerprint rejected: best=%s@%.3f margin=%.3f below required %.2f",
                best_vehicle.get("make", "?"), best_score, actual_margin, margin,
            )

        self._last_fp_score = best_score
        return None

    def _get_prototype(self, vehicle: dict) -> np.ndarray | None:
        """
        Return the L2-normalised prototype for a vehicle, rebuilding from its
        reference embeddings whenever the stored count changes.
        """
        vid = vehicle["id"]
        ref_fps = vehicle.get("reference_fingerprints") or []
        count = len(ref_fps)

        cached = self._prototype_cache.get(vid)
        if cached is not None and cached["count"] == count:
            return cached["prototype"]

        embeddings = []
        for raw in ref_fps:
            try:
                fp = json_to_fingerprint(raw if isinstance(raw, str) else str(raw))
                embeddings.append(fp.embedding)
            except Exception:
                logger.warning(
                    "Could not deserialise reference fingerprint for vehicle id=%s", vid
                )

        if not embeddings:
            self._prototype_cache.pop(vid, None)
            return None

        proto = build_prototype(embeddings)
        self._prototype_cache[vid] = {"prototype": proto, "count": count}
        logger.debug(
            "Built prototype for vehicle %s from %d embeddings (dim=%d)",
            vid, len(embeddings), len(proto),
        )
        return proto

    def _trigger_auto_learn(self, vehicle: dict, query_fp) -> None:
        """Store the live embedding as a new reference (fire-and-forget, daemon thread)."""
        from aura.core import cloud as _cloud

        def _run():
            try:
                fp_json = fingerprint_to_json(query_fp)
                _cloud.add_auto_learn_embedding(vehicle["id"], fp_json)
            except Exception as exc:
                logger.debug("Auto-learn embedding storage failed: %s", exc)

        threading.Thread(target=_run, daemon=True, name="fp-autolearn").start()

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
            "a-segment", "b-segment", "c-segment", "d-segment", "e-segment", "segment",
            "supermini", "economy car", "small family car", "large family car",
            "executive car",
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
