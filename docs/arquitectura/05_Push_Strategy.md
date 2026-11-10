# Documento de Arquitectura — Estrategia de Notificaciones Push
## Sistema BC (Bus Conectado) — Transporte Urbano Automatizado (Tacna, Perú)

> **Documento:** `docs/arquitectura/05_Push_Strategy.md`  
> **Versión:** 1.0 (Noviembre 2026)  
> **Estándar:** SWEBOK v4 / Notificaciones Push en Movilidad Urbana

---

## 1. Visión y Canales de Notificación

El ecosistema Bus Conectado utiliza una arquitectura dual de notificaciones push para mantener informado al pasajero en tres momentos clave del viaje: **Antes de abordar** (aproximación del bus), **Durante el viaje** (Live Activity y aviso de bajada) y **Después del viaje** (resumen de cobro y saldo).

```
┌────────────────────────────────────────────────────────┐
│                   BACKEND CENTRAL BC                   │
│   Motor de Eventos Telemáticos y Transacciones         │
└───────────────────────────┬────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
   ┌──────────────────────┐    ┌──────────────────────┐
   │      APNs (iOS)      │    │     FCM (Android)    │
   │ - Live Activities    │    │ - Heads-up banners   │
   │ - Dynamic Island     │    │ - Notif. con canales │
   │ - Push Silencioso    │    │ - Foreground Service │
   └──────────────────────┘    └──────────────────────┘
              │                           │
              ▼                           ▼
      iPhone 16 Pasajero           Android Smartphone
```

---

## 2. Tipología de Notificaciones y Matriz de Eventos

| Evento de Sistema | Canal / Formato | Prioridad | Sonido / Háptica | Payload Clave |
| :--- | :--- | :--- | :--- | :--- |
| **Bus Próximo al Paradero (<400m o ~2 min)** | APNs / FCM Alta | `High / Priority 10` | Campana corta / Vibración doble | `{"bus_id": 1, "stop_name": "Plaza Zela", "eta_min": 2}` |
| **Viaje Iniciado (Live Activity)** | iOS `ActivityKit` / Android Ongoing Notification | Continua | Silencioso | `{"trip_id": "...", "status": "ONBOARD", "next_stop": "P. Mercado"}` |
| **Aviso de Desembarque Inminente (400m antes)** | In-Trip Sheet / Heads-Up Push | `High / Urgent` | Melodía C5➔E5➔G5➔C6 + Háptica continua | `{"stop_target": "Mercadillo Bolognesi", "distance_m": 380}` |
| **Confirmación de Cobro (Echo)** | Standard Push | `Normal` | Tono caja registradora (880Hz) | `{"amount_pts": 7, "balance_remaining": 78}` |
| **Saldo Bajo (< 15 Puntos BC)** | Standard Push | `Low` | Silencioso | `{"current_pts": 8, "threshold": 15}` |
| **Avería Declarada por Conductor** | Alerta Roja Inmediata | `Urgent / Critical` | Alarma de emergencia | `{"bus_id": 1, "refund_pts": 7, "message": "Unidad averiada"}` |

---

## 3. Implementación Específica por Plataforma

### 3.1. En iOS (Apple Push Notification service - APNs)
* **Autenticación con Apple:** Clave criptográfica `.p8` (Token-based) asociada al `Team ID` y `Key ID` en Apple Developer Console.
* **Live Activities & Dynamic Island:**
  - Controlado mediante `ActivityKit`.
  - El backend envía actualizaciones vía endpoint `https://api.push.apple.com/3/device/<activity_push_token>`.
  - Encabezado: `apns-push-type: liveactivity`.
  - Contenido dinámico: Distancia al paradero de bajada, siguiente parada y tiempo restante.
* **Push Silencioso de Fondo:**
  - Encabezado: `apns-push-type: background` y `content-available: 1`.
  - Despierta la app por 30 segundos para recalcular geofencing sin molestar al usuario.

### 3.2. En Android (Firebase Cloud Messaging - FCM)
* **Canales de Notificación (Notification Channels):**
  1. `bc_proximity_alerts`: Importancia ALTA (aviso de llegada del bus).
  2. `bc_trip_active`: Importancia BAJA / Ongoing (tarjeta fija mientras se viaja).
  3. `bc_financial_receipts`: Importancia MEDIA (recargas y débitos).
* **WorkManager y Geofencing:**
  - Receptor en segundo plano que escucha `PendingIntent` de geocerca del bus sin drenar la batería del smartphone.

---

## 4. Gestión del Ciclo de Vida de Tokens y Privacidad

1. **Registro:** Al iniciar sesión o aceptar permisos, el dispositivo envía `device_token`, `platform` (iOS/Android) y `app_version` a `POST /api/v1/users/me/device-tokens`.
2. **Rotación:** Si el proveedor (FCM o APNs) regenera el token, la app actualiza el registro de inmediato.
3. **Invalidación Inmediata (Unsubscribe):** Al cerrar sesión o desinstalar la app, el token se desactiva (`active = false`) para evitar despachar mensajes a terminales ajenos.
4. **Política Anti-Spam:** Máximo 5 notificaciones no transaccionales por semana. Las notificaciones transaccionales (cobros, alertas de bajada) están exentas por ser de seguridad operativa.

