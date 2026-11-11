from fastapi import APIRouter, Depends, Request, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
import redis.asyncio as aioredis
from typing import Optional

from app.api.deps import get_db, get_redis, get_current_user, security_scheme
from app.core.config import settings
from app.models.user import User
from app.core.security import decode_token
from app.schemas.auth import (
    OtpSendRequest,
    OtpSendResponse,
    OtpVerifyRequest,
    TokenResponse,
    RefreshTokenRequest,
    RefreshTokenResponse,
    TestAccountsResponse,
)
from app.services.otp_service import OtpService
from app.services.auth_service import AuthService

router = APIRouter()


@router.get(
    "/test-accounts",
    response_model=TestAccountsResponse,
    status_code=status.HTTP_200_OK,
    summary="Listar cuentas de prueba preconfiguradas (Adulto, Universitario SUNEDU, CONADIS)",
    description="Devuelve los perfiles de prueba listos para usar con OTP 123456 en entorno de desarrollo."
)
async def list_test_accounts():
    return TestAccountsResponse(accounts=AuthService.get_test_accounts())


@router.post(
    "/otp/send",
    response_model=OtpSendResponse,
    status_code=status.HTTP_200_OK,
    summary="Despachar código OTP de 6 dígitos por SMS o WhatsApp (CU-00.1)",
    description="Genera y envía un código temporal de 6 dígitos (TTL 5 min) al número telefónico peruano proporcionado."
)
async def send_otp(
    payload: OtpSendRequest,
    redis: aioredis.Redis = Depends(get_redis)
):
    """
    Despacha el código de autenticación al teléfono celular del pasajero.
    Aplica límite de 3 solicitudes cada 10 minutos para mitigar ataques por SMS bombing.
    """
    _, ttl = await OtpService.generate_and_dispatch_otp(
        phone=payload.phone,
        redis_client=redis
    )
    return OtpSendResponse(
        success=True,
        message=f"Código de seguridad enviado vía SMS al {payload.phone}",
        expires_in_seconds=ttl,
        phone=payload.phone
    )


@router.post(
    "/otp/verify",
    response_model=TokenResponse,
    status_code=status.HTTP_200_OK,
    summary="Validar OTP, crear sesión única y monedero (CU-00.2 / CU-00.3 / CU-00.4)",
    description="Verifica el código de 6 dígitos contra Redis. Si el usuario es nuevo, crea su registro y monedero en 0 pts. Invalida sesiones activas en otros teléfonos."
)
async def verify_otp(
    payload: OtpVerifyRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    redis: aioredis.Redis = Depends(get_redis)
):
    """
    Paso final del Onboarding e inicio de sesión.
    Imprime la regla estricta de Sesión Única: revoca cualquier terminal anterior del usuario.
    """
    await OtpService.verify_otp(
        phone=payload.phone,
        code=payload.code,
        redis_client=redis
    )

    client_ip = request.client.host if request.client else None

    token_response = await AuthService.authenticate_or_register_user(
        db=db,
        phone=payload.phone,
        device_id=payload.device_id,
        device_name=payload.device_name,
        client_ip=client_ip
    )

    return token_response


@router.post(
    "/refresh",
    response_model=RefreshTokenResponse,
    status_code=status.HTTP_200_OK,
    summary="Renovar Access Token",
    description="Permite extender la sesión móvil sin volver a solicitar código OTP si la sesión no ha sido revocada."
)
async def refresh_token(
    payload: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db)
):
    new_access_token = await AuthService.refresh_access_token(
        db=db,
        refresh_token=payload.refresh_token
    )
    return RefreshTokenResponse(
        access_token=new_access_token,
        token_type="Bearer",
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
    )


@router.delete(
    "/logout",
    status_code=status.HTTP_200_OK,
    summary="Cerrar y revocar sesión activa del dispositivo (CU-11)",
    description="Marca la sesión actual como inactiva en base de datos e invalida el JWT en el terminal."
)
async def logout(
    current_user: User = Depends(get_current_user),
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security_scheme),
    db: AsyncSession = Depends(get_db)
):
    if not credentials or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Credenciales de autenticación no proporcionadas.",
        )
    token = credentials.credentials
    payload = decode_token(token)
    jti = payload.get("jti") if payload else None
    if not jti:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token malformado.",
        )

    await AuthService.logout(db=db, user_id=str(current_user.id), jti=jti)
    return {"success": True, "message": "Sesión cerrada correctamente."}
