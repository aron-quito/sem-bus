# Especificación Técnica de Implementación — Caso de Uso CU-00
## Módulo de Autenticación OTP por Celular, Sesión Única (Estilo Yape) e Inicialización de Monedero

> **Documento:** `docs/arquitectura/specs/CU00_Implementacion_Tecnica.md`  
> **Versión:** 1.0 (Noviembre 2026)  
> **Estándar:** SWEBOK v4 / Software Construction & Detailed Design  
> **Trazabilidad:** [CU00_Autenticacion_OTP_Onboarding.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU00/CU00_Autenticacion_OTP_Onboarding.md) | Casos `TC-AUTH-01` a `TC-AUTH-04`

---

## 1. Alcance y Arquitectura de Componentes

El Caso de Uso **CU-00** es la puerta de enlace de seguridad y creación de identidad en el ecosistema BC. Gobierna la emisión de claves temporales OTP, la verificación contra caché de alta velocidad (Redis), la creación atómica de cuenta y monedero en PostgreSQL y la imposición de sesión única por dispositivo (*single active device policy*).

```
┌────────────────────────────────────────────────────────────────────────┐
│                        FLUJO TÉCNICO CU-00                             │
└────────────────────────────────────────────────────────────────────────┘

 1. Cliente Móvil         2. API Gateway (FastAPI)     3. Redis 7 (Caché/TTL)    4. PostgreSQL 15 (ACID)
       │                             │                          │                        │
       │── POST /auth/otp/send ─────►│                          │                        │
       │   { phone: "952123456" }    │── Rate Limit Check ─────►│                        │
       │                             │── Guardar OTP Hash ─────►│ (TTL 300s)             │
       │                             │── Despacho Twilio/Meta   │                        │
       │◄── 200 OK (expires_in: 300)─│                          │                        │
       │                             │                          │                        │
       │── POST /auth/otp/verify ───►│                          │                        │
       │   { phone, code, device_id }│── Validar Hash OTP ─────►│                        │
       │                             │── Invalida OTP consumido │                        │
       │                             │── BEGIN TRANSACTION ─────────────────────────────►│
       │                             │   - SELECT or INSERT users                        │
       │                             │   - INSERT wallets (if new, points=0)             │
       │                             │   - fn_revoke_previous_sessions()                 │
       │                             │   - INSERT user_sessions                          │
       │                             │── COMMIT ────────────────────────────────────────►│
       │◄── 200 OK { access_token, ──│                                                   │
       │             refresh_token } │                                                   │
```

---

## 2. Reglas de Validación y Lógica de Negocio

### 2.1. Normalización y Formato Telefónico (Perú)
* **Regex de entrada:** `^9\d{8}$` (exactamente 9 dígitos numéricos comenzando con 9).
* **Formato E.164 canónico:** `+519XXXXXXXX`. Todas las búsquedas en base de datos y llaves en Redis se realizan con el formato canónico normalizado.

### 2.2. Generación y Almacenamiento Seguro de OTP
* **Código:** 6 dígitos numéricos aleatorios generados mediante generador criptográfico (`secrets.choice`).
* **Entorno de Demo / Sandbox:** El código `123456` está permitido únicamente si `ENV=development` o `DEBUG=True`. En staging y producción se rechaza si no coincide con el hash generado.
* **Llaves en Redis:**
  - `otp:code:{phone}`: Hash bcrypt o SHA-256(code + salt). TTL: `300` segundos (5 minutos).
  - `rate:otp:send:{phone}`: Contador de envíos por ventana de tiempo. Máximo 3 envíos por 10 minutos (TTL 600s).
  - `rate:otp:verify:{phone}`: Contador de intentos fallidos. Si llega a 3 intentos, bloqueo de verificación por 10 minutos.

### 2.3. Transacción Atómica de Inicialización (PostgreSQL)
Al validar el código correctamente:
1. **Verificación de Existencia de Usuario:**
   ```sql
   SELECT id, phone, name, role, is_active FROM users WHERE phone = :phone;
   ```
2. **Creación Atómica (si es usuario nuevo):**
   ```sql
   INSERT INTO users (phone, role, current_device_id)
   VALUES (:phone, 'ADULT', :device_id)
   RETURNING id;
   
   INSERT INTO wallets (user_id, points_balance)
   VALUES (:new_user_id, 0);
   ```
3. **Imposición de Sesión Única (CU-00.4):**
   ```sql
   -- Invocar función del DDL:
   SELECT fn_revoke_previous_sessions(:user_id, :new_jwt_jti);
   
   -- Registrar nueva sesión:
   INSERT INTO user_sessions (user_id, device_id, device_name, jwt_jti, ip_address, is_active)
   VALUES (:user_id, :device_id, :device_name, :new_jwt_jti, :client_ip, TRUE);
   
   UPDATE users SET current_device_id = :device_id, updated_at = NOW() WHERE id = :user_id;
   ```

---

## 3. Especificación de Endpoints y Contratos

### 3.1. `POST /api/v1/auth/otp/send`
* **Request:**
  ```json
  {
    "phone": "952123456"
  }
  ```
* **Responses:**
  - `200 OK`: `{"success": true, "message": "Código enviado", "expires_in_seconds": 300}`
  - `422 Unprocessable Entity`: Formato telefónico inválido.
  - `429 Too Many Requests`: `{"detail": "Demasiadas solicitudes. Intenta en X minutos."}`

### 3.2. `POST /api/v1/auth/otp/verify`
* **Request:**
  ```json
  {
    "phone": "952123456",
    "code": "123456",
    "device_id": "IPHONE16-ARON-UUID-941",
    "device_name": "iPhone 16 Pro"
  }
  ```
* **Responses:**
  - `200 OK`:
    ```json
    {
      "access_token": "eyJhbGciOi...",
      "refresh_token": "dGhpcy1pcy...",
      "token_type": "Bearer",
      "expires_in": 3600,
      "user": {
        "id": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11",
        "phone": "+51952123456",
        "name": "Pasajero BC",
        "role": "ADULT",
        "points_balance": 0,
        "is_new_user": true
      }
    }
    ```
  - `400 Bad Request`: `{"detail": "Código incorrecto o expirado"}`
  - `403 Forbidden`: `{"detail": "Teléfono bloqueado temporalmente por intentos fallidos"}`

### 3.3. `POST /api/v1/auth/refresh`
* **Request:** `{"refresh_token": "..."}`
* **Response:** `200 OK {"access_token": "...", "expires_in": 3600}`

### 3.4. `DELETE /api/v1/auth/logout`
* **Headers:** `Authorization: Bearer <token>`
* **Acción:** Marca `is_active = FALSE` en `user_sessions` para el `jti` del token y elimina la sesión en Redis.

---

## 4. Trazabilidad con Casos de Prueba (BDD)

| Test Case | Escenario BDD | Validación Implementada |
| :--- | :--- | :--- |
| `TC-AUTH-01` | Registro exitoso con número válido | `POST /auth/otp/send` ➔ `POST /auth/otp/verify` retorna tokens y crea monedero en 0 pts. |
| `TC-AUTH-02` | Rechazo de número inválido | Pydantic regex `^9\d{8}$` devuelve HTTP 422 antes de tocar base de datos. |
| `TC-AUTH-03` | Anti-fuerza bruta (3 intentos) | Redis counter `rate:otp:verify:{phone}` bloquea con HTTP 429 al 3er fallo. |
| `TC-AUTH-04` | Sesión única estilo Yape | `fn_revoke_previous_sessions` desactiva tokens previos; Dispositivo A recibe 401 en la siguiente petición. |

