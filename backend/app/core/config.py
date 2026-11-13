from typing import List
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field


class Settings(BaseSettings):
    # App General
    ENV: str = "development"
    APP_NAME: str = "Bus Conectado API"
    DEBUG: bool = True
    PORT: int = 8000
    HOST: str = "0.0.0.0"

    # Database PostgreSQL 15+ (asyncpg)
    DATABASE_URL: str = Field(
        default="postgresql+asyncpg://bc_user:bc_password@localhost:5432/bc_db"
    )
    DATABASE_POOL_SIZE: int = 20

    # Redis Cache & Pub/Sub
    REDIS_URL: str = Field(default="redis://localhost:6379/0")

    # JWT Authentication (Estilo Yape / Sesión Única)
    JWT_SECRET_KEY: str = Field(
        default="dev_secret_key_bus_conectado_tacna_peru_2026_super_secure_64_bytes"
    )
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60
    REFRESH_TOKEN_EXPIRE_DAYS: int = 90

    # Twilio / SMS Gateway
    TWILIO_ACCOUNT_SID: str = ""
    TWILIO_AUTH_TOKEN: str = ""
    TWILIO_PHONE_NUMBER: str = ""

    # Webhooks Bancarios & POS Dinámico (Estilo Yape)
    YAPE_WEBHOOK_SECRET: str = "test_yape_webhook_secret_bcp"
    PLIN_WEBHOOK_SECRET: str = "test_plin_webhook_secret_interbank"
    QR_SIGNING_SECRET: str = "dev_qr_signing_secret_bus_conectado_tacna_2026"
    POS_DEVICE_SECRET: str = "dev_pos_terminal_secret_bus_conectado_tacna_2026"
    POS_QR_TTL_SECONDS: int = 60
    DEFAULT_FLAT_FARE_POINTS: int = 15
    YAPE_EMPRESA_COMMISSION_RATE: float = 0.0295
    YAPE_EMPRESA_PHONE: str = "952000110"
    YAPE_EMPRESA_MERCHANT_NAME: str = "BUS CONECTADO TACNA"

    # CORS
    CORS_ORIGINS: List[str] = [
        "http://localhost:3000",
        "http://localhost:8000",
        "http://localhost:5173",
        "https://34.30.86.129.sslip.io",
        "http://34.30.86.129.sslip.io"
    ]

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore"
    )


settings = Settings()

