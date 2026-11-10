import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_tc_auth_01_registro_exitoso_y_creacion_monedero(client: AsyncClient):
    """
    TC-AUTH-01: Registro exitoso con número válido peruano (+519XXXXXXXX)
    Verifica que se emitan tokens JWT y el monedero se cree en 0 Puntos BC.
    """
    # 1. Solicitar código OTP
    send_res = await client.post(
        "/api/v1/auth/otp/send",
        json={"phone": "952123456"}
    )
    assert send_res.status_code == 200
    data = send_res.json()
    assert data["success"] is True
    assert data["phone"] == "+51952123456"

    # 2. Verificar código (demo "123456")
    verify_res = await client.post(
        "/api/v1/auth/otp/verify",
        json={
            "phone": "952123456",
            "code": "123456",
            "device_id": "IPHONE-16-ARON-001",
            "device_name": "iPhone 16 Pro"
        }
    )
    assert verify_res.status_code == 200
    auth_data = verify_res.json()

    assert "access_token" in auth_data
    assert "refresh_token" in auth_data
    assert auth_data["token_type"] == "Bearer"
    assert auth_data["user"]["phone"] == "+51952123456"
    assert auth_data["user"]["role"] == "ADULT"
    assert auth_data["user"]["points_balance"] == 0
    assert auth_data["user"]["is_new_user"] is True


@pytest.mark.asyncio
async def test_tc_auth_02_rechazo_numero_invalido(client: AsyncClient):
    """
    TC-AUTH-02: Rechazo de formato telefónico inválido (no empieza en 9 o longitud errónea).
    """
    # Caso A: Empieza en 8
    res1 = await client.post("/api/v1/auth/otp/send", json={"phone": "852123456"})
    assert res1.status_code == 422

    # Caso B: Menos de 9 dígitos
    res2 = await client.post("/api/v1/auth/otp/send", json={"phone": "9521234"})
    assert res2.status_code == 422


@pytest.mark.asyncio
async def test_tc_auth_03_rechazo_codigo_otp_incorrecto(client: AsyncClient):
    """
    TC-AUTH-03: Rechazo de código OTP erróneo.
    """
    await client.post("/api/v1/auth/otp/send", json={"phone": "952777888"})

    # Código incorrecto (distinto de 123456 en mock)
    res = await client.post(
        "/api/v1/auth/otp/verify",
        json={
            "phone": "952777888",
            "code": "999999",
            "device_id": "DEV-TEST-002"
        }
    )
    assert res.status_code == 400
    assert "incorrecto" in res.json()["detail"].lower()


@pytest.mark.asyncio
async def test_tc_auth_04_sesion_unica_estilo_yape(client: AsyncClient):
    """
    TC-AUTH-04: Sesión única por dispositivo (Estilo Yape).
    El inicio de sesión en Dispositivo B revoca el acceso en Dispositivo A.
    """
    phone = "952999000"

    # 1. Login en Dispositivo A
    await client.post("/api/v1/auth/otp/send", json={"phone": phone})
    res_dev_a = await client.post(
        "/api/v1/auth/otp/verify",
        json={"phone": phone, "code": "123456", "device_id": "DEVICE-A"}
    )
    assert res_dev_a.status_code == 200
    token_a = res_dev_a.json()["access_token"]

    # 2. Login en Dispositivo B con el mismo número
    await client.post("/api/v1/auth/otp/send", json={"phone": phone})
    res_dev_b = await client.post(
        "/api/v1/auth/otp/verify",
        json={"phone": phone, "code": "123456", "device_id": "DEVICE-B"}
    )
    assert res_dev_b.status_code == 200
    token_b = res_dev_b.json()["access_token"]
    assert token_a != token_b

    # 3. Intentar usar Token A (debe ser rechazado por revocación de sesión)
    headers_a = {"Authorization": f"Bearer {token_a}"}
    logout_a = await client.delete("/api/v1/auth/logout", headers=headers_a)
    assert logout_a.status_code == 401
    assert "abierto en otro dispositivo" in logout_a.json()["detail"]
