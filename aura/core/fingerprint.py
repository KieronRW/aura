import base64
import json
import logging

import cv2
import numpy as np

from aura.config.settings import FINGERPRINT_MATCH_THRESHOLD

logger = logging.getLogger(__name__)

# ─── CNN model (lazy-loaded on first extraction) ─────────────────────────────

_model = None       # torch.nn.Module — mobilenet_v2.features
_BACKEND: str | None = None   # "torch" or "classical"

_IMG_SIZE = 224
_IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
_IMAGENET_STD  = np.array([0.229, 0.224, 0.225], dtype=np.float32)


def _load_model() -> None:
    global _model, _BACKEND
    if _BACKEND is not None:
        return

    try:
        import torch
        import torchvision.models as models

        # Limit to 2 threads — leave cores for camera and display
        torch.set_num_threads(2)

        try:
            m = models.mobilenet_v2(weights="DEFAULT")
        except TypeError:
            m = models.mobilenet_v2(pretrained=True)  # older torchvision

        m.eval()
        _model = m.features   # output: (1, 1280, 7, 7) for 224×224 input
        _BACKEND = "torch"
        logger.info(
            "Fingerprint: MobileNetV2 CNN backend loaded (1280-dim embeddings)"
        )

    except Exception as exc:
        logger.warning(
            "Fingerprint: torch/torchvision unavailable (%s) — using spatial "
            "histogram fallback (less accurate for cross-angle matching)", exc,
        )
        _BACKEND = "classical"


# ─── Types ───────────────────────────────────────────────────────────────────

class Fingerprint:
    """L2-normalised embedding vector for one vehicle image."""

    def __init__(self, embedding: np.ndarray) -> None:
        self.embedding = embedding   # shape (D,) float32


# ─── Extraction ──────────────────────────────────────────────────────────────

def extract_fingerprint(image: np.ndarray) -> Fingerprint:
    """
    Extract a visual fingerprint from a BGR vehicle image.
    Uses MobileNetV2 global-average-pool features when torch is available,
    falling back to a 2×2 spatial HSV histogram otherwise.
    """
    _load_model()
    if _BACKEND == "torch":
        return _extract_cnn(image)
    return _extract_classical(image)


def _extract_cnn(image: np.ndarray) -> Fingerprint:
    import torch

    img = cv2.resize(image, (_IMG_SIZE, _IMG_SIZE))
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    img = (img - _IMAGENET_MEAN) / _IMAGENET_STD
    # (H, W, C) → (1, C, H, W)
    tensor = torch.from_numpy(img.transpose(2, 0, 1)).unsqueeze(0)

    with torch.no_grad():
        features = _model(tensor)                                              # (1, 1280, 7, 7)
        pooled   = torch.nn.functional.adaptive_avg_pool2d(features, (1, 1))  # (1, 1280, 1, 1)
        emb      = pooled.squeeze().numpy()                                    # (1280,)

    emb = _l2_normalize(emb)
    logger.debug("Fingerprint extracted — CNN dim=%d backend=torch", len(emb))
    return Fingerprint(embedding=emb)


def _extract_classical(image: np.ndarray) -> Fingerprint:
    """
    2×2 spatial grid of 32-bin HSV histograms → 384-dim L2-normalised vector.
    More robust than single-histogram matching but still weaker than CNN for
    cross-angle comparison.
    """
    h, w = image.shape[:2]
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    parts = []
    for r in range(2):
        for c in range(2):
            cell = hsv[r * h // 2:(r + 1) * h // 2, c * w // 2:(c + 1) * w // 2]
            for ch in range(3):
                hist = cv2.calcHist([cell], [ch], None, [32], [0, 256])
                cv2.normalize(hist, hist, alpha=0, beta=1, norm_type=cv2.NORM_MINMAX)
                parts.append(hist.flatten())
    emb = _l2_normalize(np.concatenate(parts))
    logger.debug("Fingerprint extracted — classical dim=%d", len(emb))
    return Fingerprint(embedding=emb)


def _l2_normalize(v: np.ndarray) -> np.ndarray:
    norm = np.linalg.norm(v)
    return (v / norm).astype(np.float32) if norm > 0 else v.astype(np.float32)


# ─── Comparison ──────────────────────────────────────────────────────────────

def compare_fingerprints(fp1: Fingerprint, fp2: Fingerprint) -> float:
    """
    Cosine similarity in [0.0, 1.0] between two L2-normalised embeddings.
    Scores >= FINGERPRINT_MATCH_THRESHOLD are considered a match.
    Returns 0.0 if embedding dimensions don't match (mixed backends).
    """
    if fp1.embedding.shape != fp2.embedding.shape:
        logger.warning(
            "Fingerprint dimension mismatch (%d vs %d) — likely mixed backends, skipping",
            len(fp1.embedding), len(fp2.embedding),
        )
        return 0.0

    score = float(np.dot(fp1.embedding, fp2.embedding))
    score = max(0.0, min(1.0, score))   # clamp for floating-point edge cases

    logger.debug(
        "Fingerprint comparison — cosine=%.4f threshold=%.2f",
        score, FINGERPRINT_MATCH_THRESHOLD,
    )
    return round(score, 4)


# ─── Serialisation ───────────────────────────────────────────────────────────

def fingerprint_to_json(fp: Fingerprint) -> str:
    return json.dumps({
        "v": 2,
        "embedding": base64.b64encode(fp.embedding.tobytes()).decode("ascii"),
        "dim": len(fp.embedding),
    })


def json_to_fingerprint(data: str) -> Fingerprint:
    payload = json.loads(data)
    if payload.get("v", 1) < 2 or "embedding" not in payload:
        raise ValueError(
            "Legacy v1 fingerprint (histogram+ORB) — "
            "clear fingerprint_data in vehicle_reference_images to re-enrol"
        )
    raw = base64.b64decode(payload["embedding"])
    dim = payload["dim"]
    emb = np.frombuffer(raw, dtype=np.float32).reshape(dim).copy()
    return Fingerprint(embedding=emb)
