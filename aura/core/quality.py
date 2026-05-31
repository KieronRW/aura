import logging

import cv2
import numpy as np

log = logging.getLogger(__name__)


def check_quality(frame: np.ndarray, settings: dict) -> tuple[bool, float]:
    """
    Run 4 quality checks on a frame. Returns (passed, score) where score is
    the fraction of checks passed (0.0–1.0).
    """
    min_crop_size  = int(settings.get("quality_min_crop_size",  100))
    min_sharpness  = float(settings.get("quality_min_sharpness", 150))
    min_brightness = float(settings.get("quality_min_brightness", 40))
    max_brightness = float(settings.get("quality_max_brightness", 220))

    checks = 4
    passed = 0

    # 1 — Minimum crop size
    h, w = frame.shape[:2]
    if w > min_crop_size and h > min_crop_size:
        passed += 1
    else:
        log.debug("Quality: crop size failed (%dx%d, min %d)", w, h, min_crop_size)

    # 2 — Blur / sharpness (Laplacian variance; higher = sharper)
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    sharpness = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    if sharpness > min_sharpness:
        passed += 1
    else:
        log.debug("Quality: sharpness failed (%.1f, min %.1f)", sharpness, min_sharpness)

    # 3 — Brightness (mean grayscale value)
    brightness = float(gray.mean())
    if min_brightness <= brightness <= max_brightness:
        passed += 1
    else:
        log.debug(
            "Quality: brightness failed (%.1f, range %.1f–%.1f)",
            brightness, min_brightness, max_brightness,
        )

    score = passed / checks
    if score == 1.0:
        log.info("Quality check passed (score=1.0)")
    return score == 1.0, score
