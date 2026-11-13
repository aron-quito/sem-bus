from typing import Optional
from pydantic import BaseModel, Field


class PosOrderCreateRequest(BaseModel):
    unit_code: str = Field(default="UNI-1408", min_length=2, max_length=32)
    plate: str = Field(default="Z4B-812", min_length=4, max_length=16)
    route_code: str = Field(default="RUTA 14", min_length=2, max_length=32)
    fixed_amount_points: int = Field(
        default=15,
        gt=0,
        le=500,
        description="Tarifa plana en puntos BC (15 pts = S/. 1.50)"
    )


class PosOrderResponse(BaseModel):
    order_id: str
    unit_code: str
    plate: str
    route_code: str
    status: str
    amount_points: int
    amount_pen: float
    ttl_seconds: int
    expires_at: str
    app_qr_payload: str
    yape_qr_payload: str
    ws_path: str
    yape_commission_rate: float
    yape_commission_pen: float
    yape_net_pen: float
    app_commission_pen: float
    app_net_pen: float


class PosOrderStatusResponse(BaseModel):
    order_id: str
    unit_code: str
    route_code: str
    status: str
    payment_method: Optional[str] = None
    fare_label: Optional[str] = None
    companions_count: int = 0
    amount_points: int
    amount_pen: float
    commission_pen: float = 0.0
    net_pen: float = 0.0
    paid_at: Optional[str] = None
    expires_at: str


class YapeEmpresaWebhookRequest(BaseModel):
    order_id: Optional[str] = None
    unit_code: Optional[str] = None
    amount_pen: float = Field(..., gt=0, le=100.0)
    operation_code: str = Field(..., min_length=3, max_length=64)
    timestamp: Optional[str] = None


class PosNfcTapRequest(BaseModel):
    order_id: str
    card_uid: str = Field(..., min_length=4, max_length=64)
    companions_count: int = Field(default=0, ge=0, le=4)

