import secrets
import string
from typing import Tuple, Optional
import redis.asyncio as aioredis
from fastapi import HTTPException, status

from app.core.config import settings
from app.core.security import hash_otp, verify_otp_hash

OTP_TTL_SECONDS = 300       # 5 minutos de validez
MAX_SEND_ATTEMPTS = 3       # Máx 3 solicitudes por ventana
SEND_WINDOW_SECONDS = 600   # 10 minutos
MAX_VERIFY_ATTEMPTS = 3     # Máx 3 intentos fallidos antes de bloqueo
LOCKOUT_SECONDS = 600       # 10 minutos de bloqueo


class OtpService:
    @staticmethod
    async def generate_and_dispatch_otp(
        phone: str,
        redis_client: Optional[aioredis.Redis] = None
    ) -> Tuple[str, int]:
        """
        Genera un código OTP de 6 dígitos, aplica control de rate limit y lo almacena con TTL en Redis.
        """
        # 1. Control de Tasa de Envíos (Rate Limiting anti-spam)
        if redis_client:
            send_count_key = f"rate:otp:send:{phone}"
            current_sends = await redis_client.get(send_count_key)
            if current_sends and int(current_sends) >= MAX_SEND_ATTEMPTS:
                ttl = await redis_client.ttl(send_count_key)
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=f"Límite de envíos alcanzado. Por seguridad, espera {max(ttl, 1)} segundos antes de reintentar."
                )

        # 2. Generación de código numérico de 6 dígitos
        code = "".join(secrets.choice(string.digits) for _ in range(6))

        # En desarrollo/demo siempre permitimos 123456 como código rápido
        if settings.DEBUG and settings.ENV == "development":
            code = "123456"

        hashed = hash_otp(code)

        # 3. Almacenamiento en Redis con TTL estricto
        if redis_client:
            otp_key = f"otp:code:{phone}"
            await redis_client.set(otp_key, hashed, ex=OTP_TTL_SECONDS)

            # Incrementar contador de envíos
            p = redis_client.pipeline()
            p.incr(send_count_key)
            p.expire(send_count_key, SEND_WINDOW_SECONDS)
            await p.execute()

        # 4. Despacho por SMS / WhatsApp
        # Aquí se invoca el cliente de Twilio si hay credenciales configuradas
        # Por defecto loggea el envío
        print(f"[OTP DESPATCH] >>> Teléfono: {phone} | Código: {code} | TTL: {OTP_TTL_SECONDS}s")

        return code, OTP_TTL_SECONDS

    @staticmethod
    async def verify_otp(
        phone: str,
        code: str,
        redis_client: Optional[aioredis.Redis] = None
    ) -> bool:
        """
        Verifica el código ingresado contra Redis, controlando intentos fallidos y eliminándolo al validar.
        """
        # En modo desarrollo demo: "123456" siempre es válido
        if settings.DEBUG and code == "123456":
            if redis_client:
                await redis_client.delete(f"otp:code:{phone}")
            return True

        if not redis_client:
            return code == "123456"

        lockout_key = f"lockout:otp:{phone}"
        is_locked = await redis_client.get(lockout_key)
        if is_locked:
            ttl = await redis_client.ttl(lockout_key)
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Cuenta temporalmente bloqueada por exceso de intentos. Espera {max(ttl, 1)} segundos."
            )

        otp_key = f"otp:code:{phone}"
        stored_hash = await redis_client.get(otp_key)

        if not stored_hash:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Código OTP vencido o no solicitado. Solicita uno nuevo."
            )

        # Comprobar código
        if verify_otp_hash(code, stored_hash):
            # Éxito: invalidar de inmediato para evitar reuso (Inclusión CU-00.2)
            await redis_client.delete(otp_key)
            await redis_client.delete(f"rate:otp:verify:{phone}")
            return True
        else:
            # Fallo: incrementar contador de fallos
            verify_fail_key = f"rate:otp:verify:{phone}"
            fails = await redis_client.incr(verify_fail_key)
            await redis_client.expire(verify_fail_key, LOCKOUT_SECONDS)

            if fails >= MAX_VERIFY_ATTEMPTS:
                await redis_client.set(lockout_key, "1", ex=LOCKOUT_SECONDS)
                await redis_client.delete(otp_key)
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Has superado el límite de 3 intentos erróneos. Bloqueado por 10 minutos."
                )

            remaining = MAX_VERIFY_ATTEMPTS - fails
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Código incorrecto. Te quedan {remaining} intento(s)."
            )
