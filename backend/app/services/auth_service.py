from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException, status

from app.models.user import User, UserSession
from app.models.wallet import Wallet
from app.schemas.auth import TokenResponse, UserAuthProfile
from app.core.security import (
    generate_jti,
    create_access_token,
    create_refresh_token,
    decode_token,
)
from app.core.config import settings


class AuthService:
    @staticmethod
    async def authenticate_or_register_user(
        db: AsyncSession,
        phone: str,
        device_id: str,
        device_name: Optional[str] = None,
        client_ip: Optional[str] = None
    ) -> TokenResponse:
        """
        Ejecuta la transacción atómica de inicio de sesión o creación de usuario nuevo,
        inicializa el monedero en 0 pts y aplica la regla de Sesión Única (Estilo Yape).
        """
        is_new_user = False

        # 1. Buscar si el usuario ya existe en PostgreSQL
        stmt = select(User).where(User.phone == phone)
        result = await db.execute(stmt)
        user = result.scalar_one_or_none()

        if not user:
            # Rama A: Creación de Usuario Nuevo (CU-00.3)
            is_new_user = True
            user = User(
                phone=phone,
                name="Pasajero BC",
                role="ADULT",
                current_device_id=device_id,
                is_active=True,
            )
            db.add(user)
            await db.flush()  # Obtener user.id

            # Inicializar Monedero en 0 Puntos (Regla estricta: points_balance = 0)
            wallet = Wallet(
                user_id=user.id,
                points_balance=0,
            )
            db.add(wallet)
            await db.flush()
        else:
            # Rama B: Usuario Recurrente - Verificar que esté activo
            if not user.is_active:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Tu cuenta se encuentra inactiva o suspendida. Contacta a soporte BC."
                )

        # 2. Imponer Sesión Única por Dispositivo - Estilo Yape (Inclusión CU-00.4)
        new_jti = generate_jti()

        # Invalida todas las sesiones previas activas del usuario
        revoke_stmt = (
            update(UserSession)
            .where(
                UserSession.user_id == user.id,
                UserSession.is_active == True,
                UserSession.jwt_jti != new_jti
            )
            .values(
                is_active=False,
                revoked_at=datetime.now(timezone.utc)
            )
        )
        await db.execute(revoke_stmt)

        # Registrar la nueva sesión activa vinculada al hardware actual
        new_session = UserSession(
            user_id=user.id,
            device_id=device_id,
            device_name=device_name or "Dispositivo Móvil",
            jwt_jti=new_jti,
            ip_address=client_ip,
            is_active=True,
        )
        db.add(new_session)

        # Actualizar fingerprint del dispositivo actual en el perfil del usuario
        user.current_device_id = device_id
        user.updated_at = datetime.now(timezone.utc)

        # Commit de la transacción atómica
        await db.commit()
        await db.refresh(user)

        # 3. Obtener saldo de puntos del monedero
        wallet_stmt = select(Wallet.points_balance).where(Wallet.user_id == user.id)
        wallet_res = await db.execute(wallet_stmt)
        points = wallet_res.scalar_one_or_none() or 0

        # 4. Generar tokens seguros
        access_token = create_access_token(
            user_id=str(user.id),
            phone=user.phone,
            role=user.role,
            jti=new_jti
        )
        refresh_token = create_refresh_token(
            user_id=str(user.id),
            jti=new_jti
        )

        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            token_type="Bearer",
            expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
            user=UserAuthProfile(
                id=str(user.id),
                phone=user.phone,
                name=user.name,
                role=user.role,
                points_balance=points,
                is_new_user=is_new_user,
            )
        )

    @staticmethod
    async def refresh_access_token(
        db: AsyncSession,
        refresh_token: str
    ) -> str:
        """Valida el refresh token y emite un nuevo access token si la sesión no ha sido revocada."""
        payload = decode_token(refresh_token)
        if not payload or payload.get("type") != "refresh":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Refresh token inválido o expirado"
            )

        user_id = payload.get("sub")
        jti = payload.get("jti")

        # Verificar que la sesión continúe activa en base de datos
        stmt = select(UserSession).where(
            UserSession.user_id == user_id,
            UserSession.jwt_jti == jti,
            UserSession.is_active == True
        )
        result = await db.execute(stmt)
        session = result.scalar_one_or_none()

        if not session:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Tu sesión fue revocada al abrirse en otro dispositivo (Sesión Única Yape)."
            )

        # Obtener datos de usuario
        user_stmt = select(User).where(User.id == user_id)
        user_res = await db.execute(user_stmt)
        user = user_res.scalar_one_or_none()
        if not user:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Usuario no encontrado")

        return create_access_token(
            user_id=str(user.id),
            phone=user.phone,
            role=user.role,
            jti=jti
        )

    @staticmethod
    async def logout(
        db: AsyncSession,
        user_id: str,
        jti: str
    ) -> bool:
        """Cierra y revoca la sesión activa del usuario."""
        stmt = (
            update(UserSession)
            .where(
                UserSession.user_id == user_id,
                UserSession.jwt_jti == jti
            )
            .values(
                is_active=False,
                revoked_at=datetime.now(timezone.utc)
            )
        )
        await db.execute(stmt)
        await db.commit()
        return True
