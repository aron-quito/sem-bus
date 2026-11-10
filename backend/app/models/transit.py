import uuid
from datetime import datetime, timezone
from typing import Optional, List
from sqlalchemy import String, Integer, Float, Boolean, DateTime, ForeignKey, Uuid, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class BusRoute(Base):
    __tablename__ = "routes"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()")
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    line_number: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    color_hex: Mapped[str] = mapped_column(String(7), default="#2563EB", nullable=False)
    origin_name: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    destination_name: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    frequency_minutes: Mapped[int] = mapped_column(Integer, default=6, nullable=False)
    operating_hours: Mapped[str] = mapped_column(String(50), default="05:30 - 22:30", nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    stops: Mapped[List["BusStop"]] = relationship(
        "BusStop",
        back_populates="route",
        cascade="all, delete-orphan",
        order_by="BusStop.sequence_order"
    )
    buses: Mapped[List["Bus"]] = relationship(
        "Bus",
        back_populates="route"
    )


class BusStop(Base):
    __tablename__ = "stops"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()")
    )
    route_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("routes.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    subtitle: Mapped[Optional[str]] = mapped_column(String(150), nullable=True)
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    sequence_order: Mapped[int] = mapped_column(Integer, nullable=False)
    direction: Mapped[str] = mapped_column(String(10), default="UP", nullable=False)
    is_key_stop: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    route: Mapped["BusRoute"] = relationship("BusRoute", back_populates="stops")


class Bus(Base):
    __tablename__ = "buses"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=text("gen_random_uuid()")
    )
    route_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("routes.id", ondelete="SET NULL"),
        nullable=True,
        index=True
    )
    unit_number: Mapped[str] = mapped_column(String(20), nullable=False)
    plate: Mapped[str] = mapped_column(String(15), unique=True, nullable=False)
    driver_name: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    driver_rating: Mapped[float] = mapped_column(Float, default=4.9, nullable=False)
    occupancy_current: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    occupancy_max: Mapped[int] = mapped_column(Integer, default=32, nullable=False)
    gps_lat: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    gps_lng: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    gps_heading: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    gps_speed: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    next_stop_name: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    next_stop_eta_minutes: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    is_visible_public: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    last_telemetry_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    route: Mapped[Optional["BusRoute"]] = relationship("BusRoute", back_populates="buses")

