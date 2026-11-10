from typing import Optional, List
from pydantic import BaseModel, Field
from app.schemas.auth import StudentVerificationSchema


class LedgerTransactionSchema(BaseModel):
    id: str
    type: str
    amount_points: int
    amount_pen: float
    reference_type: Optional[str] = None
    balance_before: int
    balance_after: int
    description: str
    created_at: str


class WalletMeResponse(BaseModel):
    user_id: str
    phone: str
    name: Optional[str] = None
    role: str
    points_balance: int
    balance_pen: float
    fare_points: int
    fare_pen: float
    student_verification: Optional[StudentVerificationSchema] = None
    transactions: List[LedgerTransactionSchema] = []


class RechargeRequest(BaseModel):
    amount_points: int = Field(..., gt=0, le=5000, description="Puntos BC a recargar (ej. 50, 100, 200, 500)")
    gateway: str = Field(default="YAPE", description="YAPE o PLIN")


class RechargeResponse(BaseModel):
    success: bool = True
    message: str
    points_added: int
    new_balance_points: int
    new_balance_pen: float
    transaction: LedgerTransactionSchema


class SuneduAccreditRequest(BaseModel):
    dni: str = Field(..., min_length=8, max_length=8, description="DNI de 8 dígitos del estudiante")
    university: str = Field(default="Universidad Nacional Jorge Basadre Grohmann (UNJBG)")
    career: str = Field(default="Ingeniería en Informática y Sistemas")
    sunedu_qr_raw: Optional[str] = None


class QrPayRequest(BaseModel):
    qr_token: str = Field(..., description="Payload dinámico leído del validador POS del bus")
    companions_count: int = Field(default=0, ge=0, le=4, description="Número de acompañantes (RN-07: máx 4)")


class QrPayResponse(BaseModel):
    success: bool = True
    message: str
    holder_fare_points: int
    companions_count: int
    companions_fare_points: int
    total_points_debited: int
    total_pen_debited: float
    remaining_points: int
    transaction: LedgerTransactionSchema
