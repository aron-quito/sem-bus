# Documento de Arquitectura — Definición Formal del Stack Técnico
## Sistema BC (Bus Conectado) — Transporte Urbano Automatizado (Tacna, Perú)

> **Documento:** `docs/arquitectura/03_Stack_Tecnico.md`  
> **Versión:** 1.0 (Noviembre 2026)  
> **Estándar:** SWEBOK v4 / Architecture Decision Records (ADR)

---

## 1. Resumen de Decisiones de Arquitectura (ADR Matrix)

| Capa del Sistema | Tecnología Elegida | Versión | Alternativas Evaluadas | Justificación Principal |
| :--- | :--- | :--- | :--- | :--- |
| **Backend REST & WS** | **FastAPI (Python)** | `3.12+ / FastAPI 0.110+` | Node.js (NestJS), Go (Gin), Django | Tipado estricto con Pydantic v2, generación automática de OpenAPI 3.0, soporte nativo de WebSockets asíncronos y excelente velocidad para telemetría. |
| **Base de Datos** | **PostgreSQL** | `15.4+` | MySQL 8, MongoDB | Motor transaccional ACID estricto, extensiones geoespaciales (PostGIS), Row-Level Security (RLS) y triggers existentes para el libro mayor de puntos. |
| **Cache & Pub/Sub** | **Redis** | `7.2+ Alpine` | Memcached, RabbitMQ | Operaciones atómicas en memoria, expiración nativa por TTL para tokens OTP (5 min) y bus pub/sub de coordenadas con latencia < 2ms. |
| **App Pasajero (iOS)** | **Swift / SwiftUI** | `iOS 17.0+ / Xcode 15+` | React Native, Flutter | Rendimiento nativo a 120 FPS en mapas (MapKit), soporte directo de Dynamic Island con `ActivityKit` y seguridad nativa Keychain. |
| **App Pasajero (Android)** | **Kotlin / Compose** | `Android 13+ (API 33+)` | Flutter, React Native | Integración nativa con Google Maps SDK, lectura veloz de códigos QR mediante Google ML Kit Barcode Scanning y menor consumo de batería. |
| **App Tablet Chofer** | **Kotlin / Jetpack Compose** | `Android 12+ (API 31+)` | Flutter Web, React Native | Modo quiosco industrial confiable, layouts adaptativos en landscape y enlace estable de sockets en segundo plano. |
| **Notificaciones Push** | **FCM + APNs** | `V1 HTTP API` | OneSignal, Pusher | Canal oficial de Google y Apple con soporte para Live Activities y payloads silenciosos de telemetría sin costos de licencia de terceros. |
| **Pasarela SMS / OTP** | **Twilio + Meta API** | `API v2010 / Cloud API` | AWS SNS, Infobip | Alta tasa de entregabilidad de SMS en operadores móviles peruanos (+51) y fallback automático a WhatsApp Business API. |
| **Infraestructura MVP** | **Railway / Docker** | `Docker 26+ / Alpine Linux` | AWS ECS, Google Cloud Run | Despliegue veloz mediante contenedores, PostgreSQL y Redis administrados con cero sobrecosto devops para fase de validación en Tacna. |

---

## 2. Decisiones Arquitectónicas Detalladas (ADR)

### ADR-01: Selección del Framework de Backend (FastAPI vs Node.js NestJS)
* **Contexto:** El backend requiere despachar endpoints REST de autenticación y ledger financiero, además de mantener cientos de conexiones WebSocket simultáneas para la posición de los buses de la Línea 10.
* **Decisión:** Se elige **FastAPI (Python 3.12)** con servidor ASGI **Uvicorn**.
* **Beneficios:**
  1. Integración directa con Pydantic v2 para validación estricta de esquemas y tipos de datos peruanos (DNI, celular `9XXXXXXXX`, placas `Z1A-780`).
  2. Documentación interactiva Swagger / Redoc generada automáticamente en `/docs` sin discrepancias de código.
  3. Rendimiento parejo con Node.js en benchmarks de I/O asíncrono gracias a uvloop.

### ADR-02: Base de Datos Relacional ACID (PostgreSQL 15+)
* **Contexto:** El monedero en Puntos BC maneja fondos prepagos de usuarios reales (1 Sol = 10 pts). Está estrictamente prohibido el saldo negativo (RN-04) o el doble cobro concurrente.
* **Decisión:** Se confirma **PostgreSQL 15+** con transacciones serializables o bloqueo pesimista (`SELECT ... FOR UPDATE`).
* **Beneficios:**
  1. Triggers inmutables en base de datos (`fn_debit_wallet`, `fn_credit_wallet`) que garantizan que el saldo nunca baje de cero, incluso si el servicio web falla a mitad del cobro.
  2. Compatibilidad nativa con PostGIS para calcular distancias a paraderos y geocercas de desembarque (>150m).

### ADR-03: Desarrollo Móvil Nativo Doble (SwiftUI + Jetpack Compose)
* **Contexto:** Se analizó el uso de un framework híbrido (Flutter o React Native).
* **Decisión:** Se adopta **desarrollo nativo independiente** (SwiftUI en iOS y Jetpack Compose en Android).
* **Justificación:**
  1. **iOS:** Las Live Activities en la Dynamic Island (seguimiento del bus aproximándose mientras la app está cerrada) requieren `ActivityKit` exclusivo de Swift.
  2. **Android:** El escaneo veloz del QR en puerta en menos de 300 ms exige aceleración de hardware en cámara mediante CameraX y Google ML Kit.
  3. Los mapas de Tacna exigen renderizado suave a 60/120Hz sin sobrecalentamiento del smartphone bajo el sol tacneño.

---

## 3. Matriz de Dependencias y Versiones Exactas

### 3.1. Backend (Python 3.12)
```text
fastapi>=0.110.0,<0.111.0
uvicorn[standard]>=0.29.0
pydantic>=2.6.4
sqlalchemy>=2.0.29
asyncpg>=0.29.0
alembic>=1.13.1
redis>=5.0.3
python-jose[cryptography]>=3.3.0
passlib[bcrypt]>=1.7.4
httpx>=0.27.0
celery>=5.3.6
```

### 3.2. iOS (Swift 5.10 / iOS 17.0+)
* UI Framework: `SwiftUI`
* Mapas: `MapKit`
* Escáner QR: `AVFoundation`
* Dynamic Island: `ActivityKit`
* Almacenamiento seguro: `Security (Keychain Services)`

### 3.3. Android (Kotlin 1.9+ / API 33+)
* UI Toolkit: `androidx.compose.material3:material3:1.2.1`
* Mapas: `com.google.android.gms:play-services-maps:18.2.0`
* Escáner QR: `com.google.mlkit:barcode-scanning:17.2.0`
* Cámara: `androidx.camera:camera-camera2:1.3.2`
* Persistencia segura: `androidx.security:security-crypto:1.1.0-alpha06`
* Networking: `com.squareup.okhttp3:okhttp:4.12.0`

