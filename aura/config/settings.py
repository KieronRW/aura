import os

# Camera
CAMERA_WIDTH = int(os.getenv("AURA_CAMERA_WIDTH", 1280))
CAMERA_HEIGHT = int(os.getenv("AURA_CAMERA_HEIGHT", 720))

# Detection
MOTION_THRESHOLD = float(os.getenv("AURA_MOTION_THRESHOLD", 200))
VEHICLE_PRESENCE_SECONDS = float(os.getenv("AURA_VEHICLE_PRESENCE_SECONDS", 1.5))
YOLO_CONFIDENCE = float(os.getenv("AURA_YOLO_CONFIDENCE", 0.70))

# Fingerprinting
FINGERPRINT_MATCH_THRESHOLD = float(os.getenv("AURA_FINGERPRINT_MATCH_THRESHOLD", 0.75))

# Google Vision fallback
GOOGLE_VISION_ENABLED = os.getenv("AURA_GOOGLE_VISION_ENABLED", "true").lower() == "true"
GOOGLE_CREDENTIALS_PATH = os.path.expanduser(
    os.getenv("AURA_GOOGLE_CREDENTIALS_PATH", "~/aura/vision-key.json")
)

# Database
DATABASE_PATH = os.path.expanduser(
    os.getenv("AURA_DATABASE_PATH", "~/aura/data/vehicles.db")
)

# Network
STATIC_IP = os.getenv("AURA_STATIC_IP", "192.168.0.200")
API_PORT = int(os.getenv("AURA_API_PORT", 8000))
