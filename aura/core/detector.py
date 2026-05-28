import logging
from dataclasses import dataclass

import numpy as np

from aura.config.settings import YOLO_CONFIDENCE

logger = logging.getLogger(__name__)

# COCO class IDs that count as vehicles
_VEHICLE_CLASSES: dict[int, str] = {
    2: "car",
    3: "motorcycle",
    5: "bus",
    7: "truck",
    8: "boat",
}

_model = None


def _get_model():
    global _model
    if _model is None:
        from ultralytics import YOLO
        logger.info("Loading YOLOv8-nano model")
        _model = YOLO("yolov8n.pt")
        logger.info("YOLOv8-nano loaded")
    return _model


@dataclass
class DetectionResult:
    is_vehicle: bool
    confidence: float
    bounding_box: tuple[int, int, int, int] | None  # x, y, w, h
    vehicle_type: str | None


def detect(frame: np.ndarray) -> DetectionResult:
    """Run vehicle detection on a single BGR frame."""
    model = _get_model()

    try:
        results = model(frame, verbose=False)
    except Exception:
        logger.exception("YOLO inference failed")
        return DetectionResult(is_vehicle=False, confidence=0.0, bounding_box=None, vehicle_type=None)

    best: DetectionResult | None = None

    for result in results:
        boxes = result.boxes
        if boxes is None:
            continue

        for box in boxes:
            cls_id = int(box.cls[0])
            if cls_id not in _VEHICLE_CLASSES:
                continue

            confidence = float(box.conf[0])
            if confidence < YOLO_CONFIDENCE:
                continue

            x1, y1, x2, y2 = map(int, box.xyxy[0])
            bounding_box = (x1, y1, x2 - x1, y2 - y1)
            vehicle_type = _VEHICLE_CLASSES[cls_id]

            logger.debug(
                "Vehicle detected: %s conf=%.2f box=%s",
                vehicle_type, confidence, bounding_box,
            )

            if best is None or confidence > best.confidence:
                best = DetectionResult(
                    is_vehicle=True,
                    confidence=confidence,
                    bounding_box=bounding_box,
                    vehicle_type=vehicle_type,
                )

    if best is not None:
        logger.info(
            "Best detection: %s conf=%.2f box=%s",
            best.vehicle_type, best.confidence, best.bounding_box,
        )
        return best

    logger.debug("No vehicle detected above confidence threshold (%.2f)", YOLO_CONFIDENCE)
    return DetectionResult(is_vehicle=False, confidence=0.0, bounding_box=None, vehicle_type=None)
