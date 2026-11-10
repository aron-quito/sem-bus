# Documento de Arquitectura C4 — Nivel 2: Contenedores de Sistema
## Sistema BC (Bus Conectado) — Transporte Urbano Automatizado (Tacna, Perú)

> **Documento:** `docs/arquitectura/02_C4_Contenedores.md`  
> **Versión:** 1.0 (Noviembre 2026)  
> **Estándar:** SWEBOK v4 / Modelo C4 (Simon Brown) — Nivel 2: Containers

---

## 1. Propósito y Vista General

El diagrama de **Contenedores (C4 Level 2)** descompone el sistema central de Bus Conectado en sus unidades de software y datos ejecutables de forma independiente, detallando sus responsabilidades, tecnologías de implementación, puertos y protocolos de comunicación.

---

## 2. Diagrama C4 Nivel 2 — Contenedores

```mermaid
flowchart TD
    subgraph Clientes y Terminales
        APP_PAS["📱 App Pasajero\n(iOS SwiftUI / Android Compose)\nConsulta mapa, monedero y pago QR"]
        TAB_DRV["📟 App Conductor\n(Android Tablet 10'' Kotlin Compose)\nAforo, semáforo, botones CONADIS/avería"]
        POS_DEV["📟 Validador POS en Puerta\n(Android / Linux Embebido IoT)\nGenera QR dinámico 30s y telemetría GPS"]
        WEB_ADM["💻 Backoffice Web\n(React / Next.js Admin)\nAuditoría, gestión de flota y reportes"]
    end

    subgraph Backend Central BC (Cloud / VPS)
        API_GW["🌐 API Gateway & Backend REST\n(FastAPI / Python 3.12)\nAuth OTP, Ledger, Gestión de Rutas y Webhooks"]
        WS_HUB["⚡ WebSocket Gateway & Hub GPS\n(FastAPI WebSockets / Uvicorn)\nDistribución de telemetría y aforo en tiempo real"]
        TASK_WRK["⚙️ Worker Asíncrono de Tareas\n(Celery / Redis Queue)\nProcesamiento de Webhooks y notificaciones Push"]
        
        subgraph Almacenamiento y Mensajería
            REDIS[("⚡ Cache en Memoria & Pub/Sub\n(Redis 7.2 Alpine)\nSesiones OTP, rate limits y broker telemático")]
            PG_DB[("🗄️ Base de Datos Principal\n(PostgreSQL 15+ ACID)\n17 entidades, RLS, triggers y ledger inmutable")]
        end
    end

    APP_PAS -->|"REST HTTPS / JWT"| API_GW
    APP_PAS -->|"WSS Suscripción telemetría"| WS_HUB
    
    TAB_DRV -->|"REST HTTPS / JWT"| API_GW
    TAB_DRV -->|"WSS Sincronización aforo cabina"| WS_HUB
    
    POS_DEV -->|"REST HTTPS / mTLS"| API_GW
    POS_DEV -->|"WSS / MQTT Telemetría GPS (cada 3-5s)"| WS_HUB
    
    WEB_ADM -->|"REST HTTPS / JWT Admin"| API_GW

    API_GW -->|"Consultas y transacciones ACID"| PG_DB
    API_GW -->|"Validación OTP y sesiones activas"| REDIS
    API_GW -->|"Encola tareas pesadas"| TASK_WRK

    WS_HUB <-->|"Pub/Sub de coordenadas y aforo"| REDIS
    TASK_WRK -->|"Lectura y escritura de eventos"| PG_DB
    TASK_WRK -->|"Coordinación de colas"| REDIS
```

---

## 3. Catálogo de Contenedores y Tecnologías

| Contenedor | Tecnología | Responsabilidad Principal | Puertos / Protocolos |
| :--- | :--- | :--- | :--- |
| **App Pasajero** | Swift (SwiftUI) / Kotlin (Jetpack Compose) | Interfaz móvil nativa para consultar rutas, verificar buses en mapa, recargar saldo y pagar con QR en abordaje. | Salida HTTPS (443), WSS (443) |
| **App Conductor** | Kotlin (Jetpack Compose) Tablet | Visualización periférica de cobro, aforo semafórico en vivo, registro de pasajes CONADIS y cierre de turno. | Salida HTTPS (443), WSS (443) |
| **Validador POS** | Android Embebido / C++ daemon | Lector de cámara QR en puerta, despliegue de QR dinámico (30s TTL), módulo 4G telemático GPS. | Salida HTTPS (443), WSS (443) |
| **Backoffice Web** | Next.js 14 / Tailwind CSS | Panel de control para administradores de empresas de transporte: recaudación, kilometraje, control de choferes. | Salida HTTPS (443) |
| **Backend REST API** | FastAPI (Python 3.12) / Pydantic v2 | Lógica de negocio, autenticación OTP, procesamiento de libro mayor de Puntos BC y webhooks bancarios. | Escucha HTTP/2 (8000 detrás de Caddy/Nginx) |
| **WebSocket Hub** | FastAPI WebSockets + Starlette | Multiplexación y retransmisión de coordenadas GPS de buses y cambios de aforo a miles de clientes concurrentes. | Escucha WSS (8001 / proxy reverso) |
| **Worker Asíncrono** | Celery / Redis Queue (Python) | Despacho de notificaciones Push (APNs / FCM), conciliación de pagos Yape y generación de reportes nocturnos. | Conexión interna TCP a Redis / PG |
| **Redis Cache** | Redis 7.2 Alpine | Caché volátil con TTL estricto: códigos OTP (5 min), rate limiters anti-fuerza bruta y Pub/Sub de geoposición. | Puerto interno TCP (6379) |
| **PostgreSQL DB** | PostgreSQL 15+ (con extensiones PostGIS) | Almacenamiento relacional duradero: 17 entidades, 22 relaciones, triggers de ledger y bloqueo pesimista contra saldos negativos. | Puerto interno TCP (5432) |

---

## 4. Estrategia de WebSockets y Telemetría en Tiempo Real

### 4.1. Canales y Tópicos de Suscripción
1. `bus/{bus_id}/position`
   - **Emisor:** Validador POS / Módem telemático.
   - **Frecuencia:** Cada 3 a 5 segundos con el bus en movimiento (cada 30s detenido en paradero).
   - **Payload JSON:**
   ```json
   {
     "bus_id": 1,
     "plate": "Z1A-780",
     "line": "L10",
     "lat": -17.0142,
     "lng": -70.2519,
     "heading": 184.5,
     "speed_kmh": 28.4,
     "timestamp": "2026-11-09T22:15:00Z"
   }
   ```
2. `bus/{bus_id}/occupancy`
   - **Emisor:** Backend tras validación de pasaje o ajuste de chofer.
   - **Payload:** `{"bus_id": 1, "passengers": 23, "capacity": 32, "pct": 71, "status": "FEW_SEATS"}`.
3. `user/{user_id}/trip`
   - **Receptor:** App del pasajero a bordo.
   - **Payload:** Distancia restante a la parada de desembarque (`distance_meters: 380`, `eta_seconds: 90`).

### 4.2. Mecanismo de Fallback y Resiliencia
* **Handshake con JWT:** El cliente se autentica en la apertura del socket enviando el token en el header `Authorization: Bearer <token>` o como parámetro de query `token` firmado.
* **Heartbeat / Ping-Pong:** Ping cada 25 segundos para evitar timeouts de carriers móviles peruanos (Claro/Movistar/Entel).
* **Degradación Elegante:** Si la conexión WebSocket se interrumpe por más de 12 segundos, la app conmuta automáticamente a **HTTP Polling** sobre el endpoint `GET /api/v1/buses/active` con frecuencia de 10 segundos, reintentando la reconexión de WebSocket en background con retroceso exponencial (*exponential backoff*).

