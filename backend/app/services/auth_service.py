import uuid
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException, status

from app.models.user import User, UserSession, UserRole, StudentVerification, StudentVerificationStatus
from app.models.wallet import Wallet
from app.schemas.auth import (
    TokenResponse,
    UserAuthProfile,
    StudentVerificationSchema,
    TestAccountSeed,
)
from app.core.security import (
    generate_jti,
    create_access_token,
    create_refresh_token,
    decode_token,
)
from app.core.config import settings

# Perfiles oficiales de Cuentas de Prueba (Inician con 0 pts, 0 viajes y 0 paraderos/buses activos)
OFFICIAL_TEST_ACCOUNTS: Dict[str, Dict[str, Any]] = {
    "+51952000001": {
        "raw_phone": "952000001",
        "name": "Carlos Mendoza (Prueba Adulto)",
        "role": UserRole.ADULT.value,
        "fare_points": 15,
        "fare_pen": 1.50,
        "badge_label": "Tarifa General · 15 pts",
        "description": "Cuenta de prueba Adulto. Inicia en 0 pts, sin carné universitario y sin viajes.",
        "student_verification": None,
    },
    "+51952000002": {
        "raw_phone": "952000002",
        "name": "Aron Mamani Quispe",
        "role": UserRole.STUDENT.value,
        "fare_points": 7,
        "fare_pen": 0.70,
        "badge_label": "Universitario SUNEDU · 7 pts",
        "description": "Cuenta de prueba Universitario UNJBG verificada por SUNEDU. Inicia en 0 pts y 0 viajes.",
        "student_verification": {
            "dni": "74829103",
            "university": "Universidad Nacional Jorge Basadre Grohmann (UNJBG)",
            "career": "Ingeniería en Informática y Sistemas",
            "academic_cycle": "2026-II",
            "status": StudentVerificationStatus.ACTIVE.value,
            "expires_at": "2026-12-31",
        },
    },
    "+51952000003": {
        "raw_phone": "952000003",
        "name": "Elena Quispe (Prueba CONADIS)",
        "role": UserRole.CONADIS.value,
        "fare_points": 0,
        "fare_pen": 0.00,
        "badge_label": "Pase Libre CONADIS · 0 pts",
        "description": "Cuenta de prueba CONADIS (Ley 30412). Tarifa exonerada 0 pts. Inicia en 0 pts y 0 viajes.",
        "student_verification": None,
    },
}


def _parse_uuid(raw_id: Optional[str]) -> uuid.UUID:
    """Convierte un string de UUID en objeto uuid.UUID validado o lanza 401."""
    if not raw_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Identificador de usuario ausente en el token."
        )
    try:
        return uuid.UUID(str(raw_id))
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Identificador de usuario inválido en el token."
        )


class AuthService:
    @staticmethod
    def get_test_accounts() -> List[TestAccountSeed]:
        """Devuelve el catálogo de cuentas de prueba preconfiguradas."""
        result: List[TestAccountSeed] = []
        for phone, data in OFFICIAL_TEST_ACCOUNTS.items():
            sv = (
                StudentVerificationSchema(**data["student_verification"])
                if data["student_verification"]
                else None
            )
            result.append(
                TestAccountSeed(
                    phone=phone,
                    raw_phone=data["raw_phone"],
                    name=data["name"],
                    role=data["role"],
                    fare_points=data["fare_points"],
                    fare_pen=data["fare_pen"],
                    badge_label=data["badge_label"],
                    description=data["description"],
                    otp_code="123456",
                    student_verification=sv,
                )
            )
        return result

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
        Si el teléfono corresponde a una Cuenta de Prueba oficial, asigna su rol y acreditación.
        """
        is_new_user = False
        test_preset = OFFICIAL_TEST_ACCOUNTS.get(phone)

        # 1. Buscar si el usuario ya existe en PostgreSQL
        stmt = select(User).where(User.phone == phone)
        result = await db.execute(stmt)
        user = result.scalar_one_or_none()

        if not user:
            # Rama A: Creación de Usuario Nuevo (CU-00.3) o Cuenta de Prueba
            is_new_user = True
            default_name = test_preset["name"] if test_preset else "Pasajero BC"
            default_role = test_preset["role"] if test_preset else UserRole.ADULT.value

            user = User(
                phone=phone,
                name=default_name,
                role=default_role,
                current_device_id=device_id,
                is_active=True,
            )
            db.add(user)
            await db.flush()

            # Inicializar Monedero en 0 Puntos (Regla estricta: points_balance = 0)
            wallet = Wallet(
                user_id=user.id,
                points_balance=0,
            )
            db.add(wallet)
            await db.flush()

            # Si es la cuenta de prueba Universitaria, registrar su verificación SUNEDU
            if test_preset and test_preset.get("student_verification"):
                sv_data = test_preset["student_verification"]
                sv = StudentVerification(
                    user_id=user.id,
                    dni=sv_data["dni"],
                    university=sv_data["university"],
                    career=sv_data["career"],
                    academic_cycle=sv_data["academic_cycle"],
                    status=StudentVerificationStatus.ACTIVE.value,
                    expires_at=datetime(2026, 12, 31, 23, 59, 59, tzinfo=timezone.utc),
                )
                db.add(sv)
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

        revoke_stmt = (
            update(UserSession)
            .where(
                UserSession.user_id == user.id,
                UserSession.is_active.is_(True),
                UserSession.jwt_jti != new_jti
            )
            .values(
                is_active=False,
                revoked_at=datetime.now(timezone.utc)
            )
        )
        await db.execute(revoke_stmt)

        new_session = UserSession(
            user_id=user.id,
            device_id=device_id,
            device_name=device_name or "Dispositivo Móvil",
            jwt_jti=new_jti,
            ip_address=client_ip,
            is_active=True,
        )
        db.add(new_session)

        user.current_device_id = device_id
        user.updated_at = datetime.now(timezone.utc)

        await db.commit()
        await db.refresh(user)

        # 3. Obtener saldo de puntos del monedero
        wallet_stmt = select(Wallet.points_balance).where(Wallet.user_id == user.id)
        wallet_res = await db.execute(wallet_stmt)
        points = wallet_res.scalar_one_or_none()
        if points is None:
            wallet = Wallet(user_id=user.id, points_balance=0)
            db.add(wallet)
            await db.commit()
            points = 0

        # 4. Cargar acreditación SUNEDU si existe
        sv_stmt = select(StudentVerification).where(StudentVerification.user_id == user.id)
        sv_res = await db.execute(sv_stmt)
        sv_row = sv_res.scalar_one_or_none()
        sv_schema: Optional[StudentVerificationSchema] = None
        if sv_row:
            sv_schema = StudentVerificationSchema(
                dni=sv_row.dni,
                university=sv_row.university or "UNJBG Tacna",
                career=sv_row.career,
                academic_cycle=sv_row.academic_cycle,
                status=sv_row.status,
                expires_at=sv_row.expires_at.strftime("%Y-%m-%d") if sv_row.expires_at else "2026-12-31",
            )

        # 5. Generar tokens seguros
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
                student_verification=sv_schema,
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

        user_uuid = _parse_uuid(payload.get("sub"))
        jti = payload.get("jti")

        stmt = select(UserSession).where(
            UserSession.user_id == user_uuid,
            UserSession.jwt_jti == jti,
            UserSession.is_active.is_(True)
        )
        result = await db.execute(stmt)
        session = result.scalar_one_or_none()

        if not session:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Tu sesión fue revocada al abrirse en otro dispositivo (Sesión Única Yape)."
            )

        user_stmt = select(User).where(User.id == user_uuid)
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
        user_uuid = _parse_uuid(user_id)
        stmt = (
            update(UserSession)
            .where(
                UserSession.user_id == user_uuid,
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
