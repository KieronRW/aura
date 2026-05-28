import base64
import json
import logging

import cv2
import numpy as np

from aura.config.settings import FINGERPRINT_MATCH_THRESHOLD

logger = logging.getLogger(__name__)

# ORB keeps this many keypoints — enough for good matching, cheap on Pi 5
_MAX_ORB_FEATURES = 256

# Weight of histogram vs descriptor similarity in the final score
_HIST_WEIGHT = 0.4
_DESC_WEIGHT = 0.6

_orb = cv2.ORB_create(nfeatures=_MAX_ORB_FEATURES)
_bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)


# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

class Fingerprint:
    """Container for one vehicle's visual fingerprint."""

    def __init__(self, histogram: np.ndarray, descriptors: np.ndarray | None):
        self.histogram = histogram          # shape (48,) — 16 bins × 3 channels
        self.descriptors = descriptors      # shape (N, 32) uint8, or None


# ---------------------------------------------------------------------------
# Extraction
# ---------------------------------------------------------------------------

def extract_fingerprint(image: np.ndarray) -> Fingerprint:
    """
    Extract a visual fingerprint from a BGR vehicle image.
    Crops the centre 80% to reduce background influence.
    """
    h, w = image.shape[:2]
    margin_y, margin_x = int(h * 0.1), int(w * 0.1)
    roi = image[margin_y:h - margin_y, margin_x:w - margin_x]

    histogram = _extract_histogram(roi)
    descriptors = _extract_descriptors(roi)

    logger.debug(
        "Fingerprint extracted — descriptor count: %d",
        len(descriptors) if descriptors is not None else 0,
    )
    return Fingerprint(histogram=histogram, descriptors=descriptors)


def _extract_histogram(image: np.ndarray) -> np.ndarray:
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    hists = []
    for channel, bins in enumerate([16, 16, 16]):
        hist = cv2.calcHist([hsv], [channel], None, [bins], [0, 256])
        cv2.normalize(hist, hist, alpha=0, beta=1, norm_type=cv2.NORM_MINMAX)
        hists.append(hist.flatten())
    return np.concatenate(hists)  # (48,)


def _extract_descriptors(image: np.ndarray) -> np.ndarray | None:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    _, descriptors = _orb.detectAndCompute(gray, None)
    return descriptors  # None if no keypoints found


# ---------------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------------

def compare_fingerprints(fp1: Fingerprint, fp2: Fingerprint) -> float:
    """
    Return a similarity score in [0.0, 1.0].
    Scores >= FINGERPRINT_MATCH_THRESHOLD are considered a match.
    """
    hist_score = _compare_histograms(fp1.histogram, fp2.histogram)

    if fp1.descriptors is not None and fp2.descriptors is not None:
        desc_score = _compare_descriptors(fp1.descriptors, fp2.descriptors)
        score = _HIST_WEIGHT * hist_score + _DESC_WEIGHT * desc_score
    else:
        # Fall back to histogram only when ORB found no keypoints in one image
        score = hist_score

    logger.debug(
        "Fingerprint comparison — hist=%.3f desc=%s final=%.3f threshold=%.2f",
        hist_score,
        f"{desc_score:.3f}" if fp1.descriptors is not None and fp2.descriptors is not None else "n/a",
        score,
        FINGERPRINT_MATCH_THRESHOLD,
    )
    return round(float(score), 4)


def _compare_histograms(h1: np.ndarray, h2: np.ndarray) -> float:
    # Bhattacharyya distance → convert to similarity
    distance = cv2.compareHist(
        h1.astype(np.float32),
        h2.astype(np.float32),
        cv2.HISTCMP_BHATTACHARYYA,
    )
    return float(1.0 - distance)


def _compare_descriptors(d1: np.ndarray, d2: np.ndarray) -> float:
    matches = _bf.match(d1, d2)
    if not matches:
        return 0.0

    # Normalise by the max possible Hamming distance for ORB (256 bits = 32 bytes)
    avg_distance = np.mean([m.distance for m in matches])
    return float(1.0 - avg_distance / 256.0)


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

def fingerprint_to_json(fp: Fingerprint) -> str:
    payload = {
        "histogram": fp.histogram.tolist(),
        "descriptors": (
            base64.b64encode(fp.descriptors.tobytes()).decode("ascii")
            if fp.descriptors is not None else None
        ),
        "descriptor_count": (
            len(fp.descriptors) if fp.descriptors is not None else 0
        ),
    }
    return json.dumps(payload)


def json_to_fingerprint(data: str) -> Fingerprint:
    payload = json.loads(data)
    histogram = np.array(payload["histogram"], dtype=np.float32)

    descriptors = None
    if payload.get("descriptors"):
        raw = base64.b64decode(payload["descriptors"])
        count = payload["descriptor_count"]
        descriptors = np.frombuffer(raw, dtype=np.uint8).reshape(count, 32)

    return Fingerprint(histogram=histogram, descriptors=descriptors)
