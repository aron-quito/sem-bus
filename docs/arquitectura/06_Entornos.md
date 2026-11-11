# Documento de Arquitectura — Gestión de Entornos y Política de Secretos
## Sistema BC (Bus Conectado) — Transporte Urbano Automatizado (Tacna, Perú)

> **Documento:** `docs/arquitectura/06_Entornos.md`  
> **Versión:** 1.0 (Noviembre 2026)  
> **Estándar:** SWEBOK v4 / The Twelve-Factor App (Config)

---

## 1. Topología de Entornos de Despliegue

El ciclo de vida del software BC opera a través de tres entornos estrictamente aislados:

```
┌────────────────────────┐      ┌────────────────────────┐      ┌────────────────────────┐
│     DEVELOPMENT        │      │        STAGING         │      │       PRODUCTION       │
│ - Local / Docker       │ ───► │ - Railway (develop)    │ ───► │ - Railway (main)       │
│ - Base de datos dummy  │      │ - Datos anonimizados   │      │ - Datos financieros OK │
│ - Sandbox Twilio/Yape  │      │ - QA & Pruebas en ruta │      │ - Monitoreo real Tacna │
└────────────────────────┘      └────────────────────────┘      └────────────────────────┘
```

| Atributo | Entorno Local (Development) | Entorno de Pruebas (Staging) | Entorno Real (Production) |
| :--- | :--- | :--- | :--- |
| **Infraestructura** | Docker Compose en máquina del dev | Railway.app / Servidor Cloud | Railway.app / Servidor Cloud |
| **Dominio API** | `http://localhost:8000` | `https://staging-api.bc-tacna.pe` | `https://api.bc-tacna.pe` |
| **Base de Datos** | PostgreSQL 15 local (`bc_dev`) | PostgreSQL administrado (`bc_staging`) | PostgreSQL administrado con réplica y backups cada 6h |
| **Redis** | Redis 7 local (`redis:6379`) | Redis administrado (`tls://...`) | Redis cluster con persistencia AOF |
| **Pasarela SMS** | Twilio Test Credentials / Logs de consola | Twilio Sandbox limitado | Twilio Production + Meta WhatsApp Cloud API |
| **Pasarela Yape** | Simulador Webhook local | Yape Sandbox oficial | Yape Webhook con validación estricta HMAC |

---

## 2. Matriz de Variables de Entorno y Secretos

```ini
# ========================================================
# ARCHIVO DE CONFIGURACIÓN DE REFERENCIA (.env.example)
# ========================================================

# Configuración del Sistema
ENV=development                                      # development | staging | production
APP_NAME="Bus Conectado Backend"
DEBUG=true
PORT=8000

# Base de Datos PostgreSQL
DATABASE_URL=postgresql+asyncpg://bc_user:bc_pass@localhost:5432/bc_db
DATABASE_POOL_SIZE=20

# Cache y Pub/Sub Redis
REDIS_URL=redis://localhost:6379/0

# Criptografía y JWT (Sesión única estilo Yape)
JWT_SECRET_KEY=cambiar_por_cadena_criptografica_aleatoria_64_bytes
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60
REFRESH_TOKEN_EXPIRE_DAYS=90

# Pasarela SMS / OTP (Twilio)
TWILIO_ACCOUNT_SID=ACXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
TWILIO_AUTH_TOKEN=YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY
TWILIO_PHONE_NUMBER=+15551234567

# Pasarela Yape / Plin Webhooks
YAPE_WEBHOOK_SECRET=secreto_firma_hmac_sha256_bcp
PLIN_WEBHOOK_SECRET=secreto_firma_hmac_sha256_interbank

# Notificaciones Push
FCM_SERVICE_ACCOUNT_JSON={"type":"service_account",...}
APNS_KEY_ID=ABC1234XYZ
APNS_TEAM_ID=DEF5678UVW
APNS_BUNDLE_ID=pe.edu.unjbg.busconectado
```

---

## 3. Manifiesto Docker Compose para Desarrollo Local

El siguiente archivo `docker-compose.yml` permite levantar el ecosistema completo en menos de 2 minutos:

```yaml
version: '3.8'

services:
  # Base de Datos PostgreSQL con PostGIS
  postgres:
    image: postgis/postgis:15-3.4-alpine
    container_name: bc_postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: bc_user
      POSTGRES_PASSWORD: bc_password
      POSTGRES_DB: bc_db
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ../docs/modelo_datos/02_Script_SQL_DDL.sql:/docker-entrypoint-initdb.d/init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U bc_user -d bc_db"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Cache en Memoria y Broker Pub/Sub
  redis:
    image: redis:7.2-alpine
    container_name: bc_redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    volumes:
      - redisdata:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  pgdata:
  redisdata:
```

---

## 4. Política Estricta de Gestión de Secretos

1. **Cero Secretos en el Repositorio de Git:** El archivo `.env` está expresamente registrado en `.gitignore`. Todo commit que incluya una credencial real será rechazado por los pre-commit hooks (`git-secrets` / `detect-secrets`).
2. **Almacenamiento Nativo en Clientes Móviles:**
   * **iOS:** El `access_token` y `refresh_token` se almacenan en el **Keychain** del sistema operativo con atributo `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Nunca en `UserDefaults` ni archivos plist.
   * **Android:** Se emplea **EncryptedSharedPreferences** mediante la librería `androidx.security:security-crypto` respaldada por Android Keystore.
3. **CI/CD Seguro:** Los pipelines de GitHub Actions inyectan los secretos exclusivamente en tiempo de compilación y despliegue a través de **GitHub Encrypted Secrets**.

