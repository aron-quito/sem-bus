from typing import Optional, List
from pydantic import BaseModel


class BusStopSchema(BaseModel):
    id: str
    route_id: str
    name: str
    subtitle: Optional[str] = None
    latitude: float
    longitude: float
    sequence_order: int
    direction: str = "UP"
    is_key_stop: bool = False


class ActiveBusSchema(BaseModel):
    id: str
    route_id: Optional[str] = None
    unit_number: str
    plate: str
    line_number: str = "10"
    driver_name: Optional[str] = None
    driver_rating: float = 4.9
    occupancy_current: int = 0
    occupancy_max: int = 32
    latitude: float
    longitude: float
    heading: float = 0.0
    speed_kmh: float = 0.0
    next_stop_name: Optional[str] = None
    next_stop_eta_minutes: Optional[int] = None


class BusRouteSchema(BaseModel):
    id: str
    name: str
    line_number: str
    color_hex: str = "#2563EB"
    origin_name: Optional[str] = None
    destination_name: Optional[str] = None
    frequency_minutes: int = 6
    operating_hours: str = "05:30 - 22:30"
    stops: List[BusStopSchema] = []


class TransitNetworkResponse(BaseModel):
    routes: List[BusRouteSchema] = []
    stops: List[BusStopSchema] = []
    active_buses: List[ActiveBusSchema] = []
    has_active_service: bool = False
    empty_reason: str = "No existen rutas, paraderos ni unidades en servicio activo actualmente."
