from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional
import uuid
import hashlib
import hmac

from jose import jwt, JWTError

from app.core.config import settings


def generate_jti() -> str:
    """Genera un UUIDv4 único como identificador de sesión para revocación (Yape-style)."""
    return str(uuid.uuid4())


def create_access_token(
    user_id: str,
    phone: str,
    role: str,
    jti: str,
    expires_delta: Optional[timedelta] = None
) -> str:
    """Emite un JWT de acceso con claims para autorización rápida."""
    now = datetime.now(timezone.utc)
    if expires_delta:
        expire = now + expires_delta
    else:
        expire = now + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)

    to_encode: Dict[str, Any] = {
        "sub": str(user_id),
        "phone": phone,
        "role": role,
        "jti": jti,
        "type": "access",
        "iat": int(now.timestamp()),
        "exp": int(expire.timestamp()),
    }
    return jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def create_refresh_token(
    user_id: str,
    jti: str,
    expires_delta: Optional[timedelta] = None
) -> str:
    """Emite un Refresh Token duradero para renovación segura."""
    now = datetime.now(timezone.utc)
    if expires_delta:
        expire = now + expires_delta
    else:
        expire = now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)

    to_encode: Dict[str, Any] = {
        "sub": str(user_id),
        "jti": jti,
        "type": "refresh",
        "iat": int(now.timestamp()),
        "exp": int(expire.timestamp()),
    }
    return jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def decode_token(token: str) -> Optional[Dict[str, Any]]:
    """Decodifica y valida la firma criptográfica de un JWT."""
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM]
        )
        return payload
    except JWTError:
        return None


def hash_otp(code: str, salt: str = "bc_tacna_otp_salt") -> str:
    """Genera un hash SHA-256 salteado del código numérico para almacenamiento seguro en Redis."""
    return hashlib.sha256(f"{code}:{salt}".encode("utf-8")).hexdigest()


def verify_otp_hash(code: str, hashed: str, salt: str = "bc_tacna_otp_salt") -> bool:
    """Compara en tiempo constante (hmac.compare_digest) el código ingresado contra el hash en caché."""
    candidate = hashlib.sha256(f"{code}:{salt}".encode("utf-8")).hexdigest()
    return hmac.compare_digest(candidate, hashed)
