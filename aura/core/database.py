"""
AURA Phase 7 database layer.

Tables
------
vehicles        — registered vehicles and their owners
recognition_logs — every recognition event with full metadata
settings        — runtime key/value configuration with descriptions
users           — household users / smart-home integrations (future)
faces           — face encodings linked to vehicles (Phase 10)

Migration note: Phase 7 renames several columns from the Phase 1 schema.
Run alembic upgrade head (or drop-and-recreate in dev) before using this module.
"""

import enum
import json
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Column,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    Text,
    UniqueConstraint,
    create_engine,
    event,
)
from sqlalchemy.orm import DeclarativeBase, Session, relationship

from aura.config.settings import DATABASE_PATH


# ---------------------------------------------------------------------------
# Engine
# ---------------------------------------------------------------------------

engine = create_engine(
    f"sqlite:///{DATABASE_PATH}",
    echo=False,
    connect_args={"check_same_thread": False},
)


@event.listens_for(engine, "connect")
def _set_sqlite_pragmas(conn, _):
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("PRAGMA journal_mode=WAL")   # concurrent read/write
    conn.execute("PRAGMA synchronous=NORMAL") # safe but faster than FULL


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

class RecognitionMethod(str, enum.Enum):
    VISION       = "vision"
    FINGERPRINT  = "fingerprint"
    YOLO         = "yolo"


class SmartHomeSystem(str, enum.Enum):
    CONTROL4       = "Control4"
    SAVANT         = "Savant"
    CRESTRON       = "Crestron"
    HOME_ASSISTANT = "HomeAssistant"
    NONE           = "none"


# ---------------------------------------------------------------------------
# Base
# ---------------------------------------------------------------------------

class Base(DeclarativeBase):
    pass


# ---------------------------------------------------------------------------
# Vehicle
# ---------------------------------------------------------------------------

class Vehicle(Base):
    __tablename__ = "vehicles"
    __table_args__ = (
        Index("ix_vehicles_make_model", "make", "model"),
        Index("ix_vehicles_registered_at", "registered_at"),
        Index("ix_vehicles_is_active", "is_active"),
        CheckConstraint(
            "confidence_threshold BETWEEN 0.0 AND 1.0",
            name="ck_vehicles_confidence_range",
        ),
    )

    id                  = Column(Integer, primary_key=True, autoincrement=True)
    make                = Column(String(64),  nullable=False)
    model               = Column(String(64),  nullable=False)
    year                = Column(Integer)
    owner_name          = Column(String(128), nullable=False)
    owner_greeting      = Column(String(256))
    custom_badge_path   = Column(String(512))
    # JSON-serialised perceptual-hash feature vector from fingerprint.py
    fingerprint_data    = Column(Text)
    # Per-vehicle confidence override; NULL means use global setting
    confidence_threshold = Column(Float)
    notes               = Column(Text)
    registered_at       = Column(DateTime, default=_utcnow, nullable=False)
    updated_at          = Column(DateTime, default=_utcnow, onupdate=_utcnow, nullable=False)
    is_active           = Column(Boolean,  default=True,   nullable=False)

    logs  = relationship("RecognitionLog", back_populates="matched_vehicle", passive_deletes=True)
    faces = relationship("Face",           back_populates="vehicle",         passive_deletes=True)

    def fingerprint(self) -> dict | None:
        return json.loads(self.fingerprint_data) if self.fingerprint_data else None

    def to_dict(self) -> dict:
        return {
            "id":                   self.id,
            "make":                 self.make,
            "model":                self.model,
            "year":                 self.year,
            "owner_name":           self.owner_name,
            "owner_greeting":       self.owner_greeting,
            "custom_badge_path":    self.custom_badge_path,
            "confidence_threshold": self.confidence_threshold,
            "notes":                self.notes,
            "registered_at":        self.registered_at.isoformat() if self.registered_at else None,
            "updated_at":           self.updated_at.isoformat()    if self.updated_at    else None,
            "is_active":            self.is_active,
        }


# ---------------------------------------------------------------------------
# RecognitionLog
# ---------------------------------------------------------------------------

class RecognitionLog(Base):
    __tablename__ = "recognition_logs"
    __table_args__ = (
        Index("ix_recognition_logs_timestamp",          "timestamp"),
        Index("ix_recognition_logs_matched_vehicle_id", "matched_vehicle_id"),
        Index("ix_recognition_logs_method_used",        "method_used"),
        CheckConstraint(
            "confidence IS NULL OR confidence BETWEEN 0.0 AND 1.0",
            name="ck_logs_confidence_range",
        ),
        CheckConstraint(
            "duration_seconds IS NULL OR duration_seconds >= 0",
            name="ck_logs_duration_positive",
        ),
    )

    id                  = Column(Integer, primary_key=True, autoincrement=True)
    timestamp           = Column(DateTime, default=_utcnow, nullable=False)
    vehicle_make        = Column(String(64))
    vehicle_model       = Column(String(64))
    matched_vehicle_id  = Column(
        Integer, ForeignKey("vehicles.id", ondelete="SET NULL"), nullable=True
    )
    confidence          = Column(Float)
    method_used         = Column(Enum(RecognitionMethod), nullable=False)
    image_path          = Column(String(512))  # path to saved frame on disk
    duration_seconds    = Column(Float)        # seconds vehicle was visible

    matched_vehicle = relationship("Vehicle", back_populates="logs")

    def to_dict(self) -> dict:
        return {
            "id":                 self.id,
            "timestamp":          self.timestamp.isoformat() if self.timestamp else None,
            "vehicle_make":       self.vehicle_make,
            "vehicle_model":      self.vehicle_model,
            "matched_vehicle_id": self.matched_vehicle_id,
            "confidence":         self.confidence,
            "method_used":        self.method_used.value if self.method_used else None,
            "image_path":         self.image_path,
            "duration_seconds":   self.duration_seconds,
        }


# ---------------------------------------------------------------------------
# Setting
# ---------------------------------------------------------------------------

# Seeded defaults written to the DB on first init_db() call.
SETTINGS_DEFAULTS: dict[str, tuple[str, str]] = {
    # key:                          (value,   description)
    "motion_sensitivity":           ("200",   "Minimum pixel-delta to trigger motion detection"),
    "recognition_cooldown":         ("30",    "Seconds before the same vehicle can be re-recognised"),
    "display_brightness":           ("80",    "Display brightness 0–100 (percent)"),
    "yolo_confidence_threshold":    ("0.70",  "Minimum YOLO detection confidence 0.0–1.0"),
    "fingerprint_match_threshold":  ("0.75",  "Minimum fingerprint similarity to count as a match"),
    "google_vision_enabled":        ("true",  "Enable Google Vision API fallback (true/false)"),
    "vehicle_presence_seconds":     ("1.5",   "Seconds a vehicle must be stationary before recognition starts"),
    "badge_keepalive_interval":     ("30",    "Seconds between badge keepalive re-sends during YOLO hold"),
    "startup_scan_enabled":         ("true",  "Run an initial recognition scan on boot (true/false)"),
}


class Setting(Base):
    __tablename__ = "settings"

    key         = Column(String(128), primary_key=True)
    value       = Column(Text, nullable=False)
    description = Column(String(512))

    def to_dict(self) -> dict:
        return {
            "key":         self.key,
            "value":       self.value,
            "description": self.description,
        }


# ---------------------------------------------------------------------------
# User  (future — Phase 8+)
# ---------------------------------------------------------------------------

class User(Base):
    __tablename__ = "users"
    __table_args__ = (
        UniqueConstraint("email", name="uq_users_email"),
        Index("ix_users_email",       "email"),
        Index("ix_users_is_active",   "is_active"),
    )

    id                = Column(Integer,  primary_key=True, autoincrement=True)
    name              = Column(String(128), nullable=False)
    email             = Column(String(256), unique=True)
    phone             = Column(String(32))
    house_address     = Column(String(512))
    smart_home_system = Column(
        Enum(SmartHomeSystem), default=SmartHomeSystem.NONE, nullable=False
    )
    registered_at     = Column(DateTime, default=_utcnow, nullable=False)
    updated_at        = Column(DateTime, default=_utcnow, onupdate=_utcnow, nullable=False)
    is_active         = Column(Boolean,  default=True,    nullable=False)

    def to_dict(self) -> dict:
        return {
            "id":                self.id,
            "name":              self.name,
            "email":             self.email,
            "phone":             self.phone,
            "house_address":     self.house_address,
            "smart_home_system": self.smart_home_system.value if self.smart_home_system else None,
            "registered_at":     self.registered_at.isoformat() if self.registered_at else None,
            "updated_at":        self.updated_at.isoformat()    if self.updated_at    else None,
            "is_active":         self.is_active,
        }


# ---------------------------------------------------------------------------
# Face  (Phase 10 — facial recognition)
# ---------------------------------------------------------------------------

class Face(Base):
    __tablename__ = "faces"
    __table_args__ = (
        Index("ix_faces_vehicle_id",  "vehicle_id"),
        Index("ix_faces_person_name", "person_name"),
        Index("ix_faces_is_active",   "is_active"),
    )

    id             = Column(Integer,  primary_key=True, autoincrement=True)
    person_name    = Column(String(128), nullable=False)
    vehicle_id     = Column(
        Integer, ForeignKey("vehicles.id", ondelete="SET NULL"), nullable=True
    )
    # pickle.dumps(numpy.ndarray, shape=(128,), dtype=float64) — face_recognition encoding
    face_encodings = Column(LargeBinary, nullable=False)
    registered_at  = Column(DateTime, default=_utcnow, nullable=False)
    updated_at     = Column(DateTime, default=_utcnow, onupdate=_utcnow, nullable=False)
    is_active      = Column(Boolean,  default=True,    nullable=False)

    vehicle = relationship("Vehicle", back_populates="faces")

    def to_dict(self) -> dict:
        return {
            "id":           self.id,
            "person_name":  self.person_name,
            "vehicle_id":   self.vehicle_id,
            "registered_at": self.registered_at.isoformat() if self.registered_at else None,
            "updated_at":   self.updated_at.isoformat()    if self.updated_at    else None,
            "is_active":    self.is_active,
            # face_encodings omitted — binary blob, not serialisable to JSON
        }


# ---------------------------------------------------------------------------
# DB lifecycle
# ---------------------------------------------------------------------------

def init_db() -> None:
    Base.metadata.create_all(engine)
    _seed_settings()


def _seed_settings() -> None:
    """Insert default settings rows that don't already exist."""
    with Session(engine) as session:
        for key, (value, description) in SETTINGS_DEFAULTS.items():
            if not session.get(Setting, key):
                session.add(Setting(key=key, value=value, description=description))
        session.commit()


# ---------------------------------------------------------------------------
# Vehicle CRUD
# ---------------------------------------------------------------------------

def get_all_vehicles(active_only: bool = False) -> list[dict]:
    with Session(engine) as session:
        q = session.query(Vehicle)
        if active_only:
            q = q.filter(Vehicle.is_active.is_(True))
        return [v.to_dict() for v in q.order_by(Vehicle.owner_name).all()]


def get_vehicle_by_id(vehicle_id: int) -> dict | None:
    with Session(engine) as session:
        v = session.get(Vehicle, vehicle_id)
        return v.to_dict() if v else None


def add_vehicle(
    owner_name: str,
    make: str,
    model: str,
    year: int | None = None,
    owner_greeting: str | None = None,
    custom_badge_path: str | None = None,
    fingerprint_data: dict | None = None,
    confidence_threshold: float | None = None,
    notes: str | None = None,
    is_active: bool = True,
) -> dict:
    with Session(engine) as session:
        vehicle = Vehicle(
            owner_name=owner_name,
            make=make,
            model=model,
            year=year,
            owner_greeting=owner_greeting,
            custom_badge_path=custom_badge_path,
            fingerprint_data=json.dumps(fingerprint_data) if fingerprint_data else None,
            confidence_threshold=confidence_threshold,
            notes=notes,
            is_active=is_active,
        )
        session.add(vehicle)
        session.commit()
        session.refresh(vehicle)
        return vehicle.to_dict()


def update_vehicle(vehicle_id: int, **fields: Any) -> dict | None:
    with Session(engine) as session:
        vehicle = session.get(Vehicle, vehicle_id)
        if not vehicle:
            return None
        if "fingerprint_data" in fields and isinstance(fields["fingerprint_data"], dict):
            fields["fingerprint_data"] = json.dumps(fields["fingerprint_data"])
        for key, value in fields.items():
            if hasattr(vehicle, key):
                setattr(vehicle, key, value)
        session.commit()
        session.refresh(vehicle)
        return vehicle.to_dict()


def delete_vehicle(vehicle_id: int) -> bool:
    with Session(engine) as session:
        vehicle = session.get(Vehicle, vehicle_id)
        if not vehicle:
            return False
        session.delete(vehicle)
        session.commit()
        return True


def deactivate_vehicle(vehicle_id: int) -> bool:
    """Soft-delete: sets is_active=False rather than removing the row."""
    return update_vehicle(vehicle_id, is_active=False) is not None


# ---------------------------------------------------------------------------
# Recognition log CRUD
# ---------------------------------------------------------------------------

def log_recognition(
    method_used: RecognitionMethod | str,
    vehicle_make: str | None = None,
    vehicle_model: str | None = None,
    confidence: float | None = None,
    matched_vehicle_id: int | None = None,
    image_path: str | None = None,
    duration_seconds: float | None = None,
) -> dict:
    if isinstance(method_used, str):
        method_used = RecognitionMethod(method_used)
    with Session(engine) as session:
        entry = RecognitionLog(
            vehicle_make=vehicle_make,
            vehicle_model=vehicle_model,
            matched_vehicle_id=matched_vehicle_id,
            confidence=confidence,
            method_used=method_used,
            image_path=image_path,
            duration_seconds=duration_seconds,
        )
        session.add(entry)
        session.commit()
        session.refresh(entry)
        return entry.to_dict()


def get_recent_logs(limit: int = 50) -> list[dict]:
    with Session(engine) as session:
        rows = (
            session.query(RecognitionLog)
            .order_by(RecognitionLog.timestamp.desc())
            .limit(limit)
            .all()
        )
        return [r.to_dict() for r in rows]


def get_logs_for_vehicle(vehicle_id: int, limit: int = 100) -> list[dict]:
    with Session(engine) as session:
        rows = (
            session.query(RecognitionLog)
            .filter(RecognitionLog.matched_vehicle_id == vehicle_id)
            .order_by(RecognitionLog.timestamp.desc())
            .limit(limit)
            .all()
        )
        return [r.to_dict() for r in rows]


# ---------------------------------------------------------------------------
# Settings CRUD
# ---------------------------------------------------------------------------

def get_settings() -> dict[str, str]:
    with Session(engine) as session:
        return {row.key: row.value for row in session.query(Setting).all()}


def get_setting(key: str, default: str | None = None) -> str | None:
    with Session(engine) as session:
        row = session.get(Setting, key)
        return row.value if row else default


def update_setting(key: str, value: str, description: str | None = None) -> None:
    with Session(engine) as session:
        row = session.get(Setting, key)
        if row:
            row.value = value
            if description is not None:
                row.description = description
        else:
            session.add(Setting(key=key, value=value, description=description))
        session.commit()


def get_settings_full() -> list[dict]:
    """Return all settings rows including description fields."""
    with Session(engine) as session:
        return [row.to_dict() for row in session.query(Setting).order_by(Setting.key).all()]


# ---------------------------------------------------------------------------
# User CRUD  (Phase 8+)
# ---------------------------------------------------------------------------

def add_user(
    name: str,
    email: str | None = None,
    phone: str | None = None,
    house_address: str | None = None,
    smart_home_system: SmartHomeSystem | str = SmartHomeSystem.NONE,
) -> dict:
    if isinstance(smart_home_system, str):
        smart_home_system = SmartHomeSystem(smart_home_system)
    with Session(engine) as session:
        user = User(
            name=name,
            email=email,
            phone=phone,
            house_address=house_address,
            smart_home_system=smart_home_system,
        )
        session.add(user)
        session.commit()
        session.refresh(user)
        return user.to_dict()


def get_all_users(active_only: bool = True) -> list[dict]:
    with Session(engine) as session:
        q = session.query(User)
        if active_only:
            q = q.filter(User.is_active.is_(True))
        return [u.to_dict() for u in q.order_by(User.name).all()]


def update_user(user_id: int, **fields: Any) -> dict | None:
    with Session(engine) as session:
        user = session.get(User, user_id)
        if not user:
            return None
        if "smart_home_system" in fields and isinstance(fields["smart_home_system"], str):
            fields["smart_home_system"] = SmartHomeSystem(fields["smart_home_system"])
        for key, value in fields.items():
            if hasattr(user, key):
                setattr(user, key, value)
        session.commit()
        session.refresh(user)
        return user.to_dict()


# ---------------------------------------------------------------------------
# Face CRUD  (Phase 10)
# ---------------------------------------------------------------------------

def register_face(
    person_name: str,
    face_encodings: bytes,
    vehicle_id: int | None = None,
) -> dict:
    with Session(engine) as session:
        face = Face(
            person_name=person_name,
            vehicle_id=vehicle_id,
            face_encodings=face_encodings,
        )
        session.add(face)
        session.commit()
        session.refresh(face)
        return face.to_dict()


def get_active_faces() -> list[Face]:
    """Return ORM objects (not dicts) so callers can deserialise encodings directly."""
    with Session(engine) as session:
        session.expire_on_commit = False
        return session.query(Face).filter(Face.is_active.is_(True)).all()


def deactivate_face(face_id: int) -> bool:
    with Session(engine) as session:
        face = session.get(Face, face_id)
        if not face:
            return False
        face.is_active = False
        session.commit()
        return True
