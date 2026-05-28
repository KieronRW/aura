import json
from datetime import datetime

from sqlalchemy import (
    Boolean, Column, DateTime, Float, ForeignKey,
    Integer, String, Text, create_engine, event
)
from sqlalchemy.orm import DeclarativeBase, Session, relationship

from aura.config.settings import DATABASE_PATH


engine = create_engine(f"sqlite:///{DATABASE_PATH}", echo=False)

event.listen(engine, "connect", lambda conn, _: conn.execute("PRAGMA foreign_keys=ON"))


class Base(DeclarativeBase):
    pass


class Vehicle(Base):
    __tablename__ = "vehicles"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String, nullable=False)
    make = Column(String, nullable=False)
    model = Column(String, nullable=False)
    year = Column(Integer)
    greeting = Column(String)
    badge_path = Column(String)
    fingerprint_data = Column(Text)  # stored as JSON
    date_added = Column(DateTime, default=datetime.utcnow)
    is_active = Column(Boolean, default=True, nullable=False)

    logs = relationship("RecognitionLog", back_populates="vehicle")

    def fingerprint(self):
        return json.loads(self.fingerprint_data) if self.fingerprint_data else None

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "make": self.make,
            "model": self.model,
            "year": self.year,
            "greeting": self.greeting,
            "badge_path": self.badge_path,
            "fingerprint_data": self.fingerprint(),
            "date_added": self.date_added.isoformat() if self.date_added else None,
            "is_active": self.is_active,
        }


class RecognitionLog(Base):
    __tablename__ = "recognition_logs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    vehicle_id = Column(Integer, ForeignKey("vehicles.id", ondelete="SET NULL"), nullable=True)
    make_detected = Column(String)
    confidence = Column(Float)
    timestamp = Column(DateTime, default=datetime.utcnow)
    method_used = Column(String)  # "fingerprint", "vision", or "yolo"

    vehicle = relationship("Vehicle", back_populates="logs")

    def to_dict(self):
        return {
            "id": self.id,
            "vehicle_id": self.vehicle_id,
            "make_detected": self.make_detected,
            "confidence": self.confidence,
            "timestamp": self.timestamp.isoformat() if self.timestamp else None,
            "method_used": self.method_used,
        }


class Settings(Base):
    __tablename__ = "settings"

    key = Column(String, primary_key=True)
    value = Column(Text)


# --- DB lifecycle ---

def init_db():
    Base.metadata.create_all(engine)


# --- Vehicle CRUD ---

def get_all_vehicles(active_only: bool = False) -> list[dict]:
    with Session(engine) as session:
        query = session.query(Vehicle)
        if active_only:
            query = query.filter(Vehicle.is_active == True)
        return [v.to_dict() for v in query.all()]


def get_vehicle_by_id(vehicle_id: int) -> dict | None:
    with Session(engine) as session:
        v = session.get(Vehicle, vehicle_id)
        return v.to_dict() if v else None


def add_vehicle(
    name: str,
    make: str,
    model: str,
    year: int = None,
    greeting: str = None,
    badge_path: str = None,
    fingerprint_data: dict = None,
    is_active: bool = True,
) -> dict:
    with Session(engine) as session:
        vehicle = Vehicle(
            name=name,
            make=make,
            model=model,
            year=year,
            greeting=greeting,
            badge_path=badge_path,
            fingerprint_data=json.dumps(fingerprint_data) if fingerprint_data else None,
            is_active=is_active,
        )
        session.add(vehicle)
        session.commit()
        session.refresh(vehicle)
        return vehicle.to_dict()


def update_vehicle(vehicle_id: int, **fields) -> dict | None:
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


# --- Recognition log ---

def log_recognition(
    method_used: str,
    make_detected: str = None,
    confidence: float = None,
    vehicle_id: int = None,
) -> dict:
    with Session(engine) as session:
        entry = RecognitionLog(
            vehicle_id=vehicle_id,
            make_detected=make_detected,
            confidence=confidence,
            method_used=method_used,
        )
        session.add(entry)
        session.commit()
        session.refresh(entry)
        return entry.to_dict()


# --- Settings ---

def get_settings() -> dict:
    with Session(engine) as session:
        rows = session.query(Settings).all()
        return {row.key: row.value for row in rows}


def update_setting(key: str, value: str) -> None:
    with Session(engine) as session:
        row = session.get(Settings, key)
        if row:
            row.value = value
        else:
            session.add(Settings(key=key, value=value))
        session.commit()
