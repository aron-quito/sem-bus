from typing import Optional
from pydantic import BaseModel, Field, field_validator
import re


class OtpSendRequest(BaseModel):
    phone: str = Field(
        ...,
        description="Número celular peruano de 9 dígitos que comienza con 9 (ej. 952123456)",
        example="952123456"
    )

    @field_validator("phone")
    @classmethod
    def validate_peruvian_phone(cls, v: str) -> str:
        cleaned = re.sub(r"\D", "", v)
        # Soportar si mandan con prefijo 51
        if cleaned.startswith("51") and len(cleaned) == 11:
            cleaned = cleaned[2:]
        if not re.match(r"^9\d{8}$", cleaned):
            raise ValueError("El número celular debe ser peruano, tener 9 dígitos y empezar con 9 (ej. 952123456)")
        return f"+51{cleaned}"


class OtpSendResponse(BaseModel):
    success: bool = True
    message: str = "Código de seguridad despachado exitosamente"
    expires_in_seconds: int = 300
    phone: str


class OtpVerifyRequest(BaseModel):
    phone: str = Field(..., description="Número celular registrado")
    code: str = Field(..., min_length=6, max_length=6, description="Código numérico de 6 dígitos", example="123456")
    device_id: str = Field(..., description="Identificador único del hardware o dispositivo", example="IPHONE-UUID-941")
    device_name: Optional[str] = Field(default="Dispositivo Móvil", description="Nombre descriptivo del dispositivo")

    @field_validator("phone")
    @classmethod
    def normalize_phone(cls, v: str) -> str:
        cleaned = re.sub(r"\D", "", v)
        if cleaned.startswith("51") and len(cleaned) == 11:
            cleaned = cleaned[2:]
        if not re.match(r"^9\d{8}$", cleaned):
            raise ValueError("Número celular inválido")
        return f"+51{cleaned}"

    @field_validator("code")
    @classmethod
    def validate_code_digits(cls, v: str) -> str:
        if not v.isdigit():
            raise ValueError("El código de verificación debe contener exclusivamente dígitos numéricos")
        return v


class UserAuthProfile(BaseModel):
    id: str
    phone: str
    name: Optional[str] = None
    role: str
    points_balance: int = 0
    is_new_user: bool = False


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
    expires_in: int = 3600
    user: UserAuthProfile


class RefreshTokenRequest(BaseModel):
    refresh_token: str


class RefreshTokenResponse(BaseModel):
    access_token: str
    token_type: str = "Bearer"
    expires_in: int = 3600

