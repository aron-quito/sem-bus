from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional
import uuid
import hashlib
import hmac
import secrets

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


def generate_nonce() -> str:
    """Genera un nonce criptográfico único por orden QR para impedir ataques replay."""
    return secrets.token_urlsafe(12)


def sign_pos_qr_payload(
    order_id: str,
    unit_code: str,
    nonce: str,
    exp_ts: int,
    fixed_points: int,
    secret: Optional[str] = None,
) -> str:
    """Genera un payload QR dinámico único firmado con HMAC-SHA256."""
    signing_key = (secret or settings.QR_SIGNING_SECRET).encode("utf-8")
    canonical = f"BC-POS|v1|{order_id}|{unit_code}|{nonce}|{exp_ts}|{fixed_points}"
    sig = hmac.new(signing_key, canonical.encode("utf-8"), hashlib.sha256).hexdigest()[:32]
    return f"{canonical}|{sig}"


def verify_pos_qr_payload(
    qr_token: str,
    now_ts: Optional[int] = None,
    secret: Optional[str] = None,
) -> Dict[str, Any]:
    """Valida firma HMAC en tiempo constante y expiración de un QR dinámico del POS."""
    parts = (qr_token or "").strip().split("|")
    if len(parts) != 8 or parts[0] != "BC-POS" or parts[1] != "v1":
        raise ValueError("Formato de código QR POS inválido.")

    _, _, order_id, unit_code, nonce, exp_raw, fixed_raw, provided_sig = parts
    try:
        exp_ts = int(exp_raw)
        fixed_points = int(fixed_raw)
    except ValueError as exc:
        raise ValueError("Metadatos numéricos inválidos en el QR.") from exc

    canonical = f"BC-POS|v1|{order_id}|{unit_code}|{nonce}|{exp_ts}|{fixed_points}"
    signing_key = (secret or settings.QR_SIGNING_SECRET).encode("utf-8")
    expected_sig = hmac.new(signing_key, canonical.encode("utf-8"), hashlib.sha256).hexdigest()[:32]

    if not hmac.compare_digest(provided_sig, expected_sig):
        raise ValueError("Firma criptográfica del QR inválida o manipulada.")

    current_ts = now_ts if now_ts is not None else int(datetime.now(timezone.utc).timestamp())
    if current_ts > exp_ts:
        raise ValueError("El código QR ha expirado. Escanea el nuevo QR en pantalla.")

    return {
        "order_id": order_id,
        "unit_code": unit_code,
        "nonce": nonce,
        "exp_ts": exp_ts,
        "fixed_points": fixed_points,
    }


def sign_yape_webhook_payload(raw_body: str, secret: Optional[str] = None) -> str:
    """Firma HMAC-SHA256 para autenticar webhooks de confirmación de Yape Empresas."""
    key = (secret or settings.YAPE_WEBHOOK_SECRET).encode("utf-8")
    return hmac.new(key, raw_body.encode("utf-8"), hashlib.sha256).hexdigest()


def verify_yape_webhook_signature(raw_body: str, signature: str, secret: Optional[str] = None) -> bool:
    """Verifica firma HMAC-SHA256 de webhook Yape en tiempo constante."""
    if not signature:
        return False
    expected = sign_yape_webhook_payload(raw_body, secret=secret)
    return hmac.compare_digest(signature.strip().lower(), expected.lower())


def build_yape_empresa_qr_payload(
    order_id: str,
    amount_pen: float,
    merchant_name: Optional[str] = None,
    phone: Optional[str] = None,
) -> str:
    """Construye payload de cobro Yape Empresas a monto fijo para mostrar en el POS."""
    m_name = (merchant_name or settings.YAPE_EMPRESA_MERCHANT_NAME).strip()
    m_phone = (phone or settings.YAPE_EMPRESA_PHONE).strip()
    return f"BC-YAPE|v1|phone={m_phone}|merchant={m_name}|amount={amount_pen:.2f}|order={order_id}"
