# Proyecto BC (Bus Conectado / Sistema de Buses Automatizado)
## Documento Maestro de Especificación de Requerimientos del Sistema (SRS) - v2.0
**Fecha:** Noviembre 2026  
**Ámbito:** Tacna, Perú  
**Estado:** Requerimientos Consolidados y Blindados (Análisis Exhaustivo)

---

## 1. Visión y Arquitectura de Actores

```
┌────────────────────────────────────────────────────────────────────────┐
│                          BACKEND CENTRAL BC                            │
│           (API REST, WebSockets, Motor de Geocercas, Ledger)           │
└────────────▲─────────────────────▲────────────────────────▲────────────┘
             │                     │                        │
             │ 4G (Telemetría/GPS) │ 4G / Wi-Fi local       │ Internet Móvil
             ▼                     ▼                        ▼
   ┌───────────────────┐ ┌───────────────────┐    ┌───────────────────┐
   │    MÓDULO POS     │ │   TABLET CHOFER   │    │   APP PASAJERO    │
   │  (Maestro en bus) │ │    (En cabina)    │    │  (iOS / Android)  │
   │ - Pantalla Pasajero│ │ - Tarjetas Cobro  │    │ - Modo Invitado   │
   │ - QR Dinámico     │ │ - Turno / Cuadre  │    │ - Monedero Puntos │
   │ - Módem 4G + GPS  │ │ - Botón CONADIS   │    │ - QR Escáner      │
   │ - Webhook Yape    │ │ - Semáforo Aforo  │    │ - Desacoplamiento │
   └───────────────────┘ └───────────────────┘    └───────────────────┘
```

---

## 2. Requerimientos Funcionales Detallados por Módulo

### 2.1. Módulo 1: Identidad, Accesos y Perfiles (App Pasajero)

* **RF-PAS-01 (Modo Invitado / Explorador):**
  * Acceso irrestricto sin autenticación a la visualización de rutas, paraderos, ubicación de buses en tiempo real y semáforo de aforo.
  * Cero barreras de entrada para adopción inmediata.
* **RF-PAS-02 (Registro y Autenticación OTP por Celular):**
  * Autenticación mediante número de teléfono celular con código OTP (SMS / WhatsApp).
  * Persistencia segura de sesión (JWT con Refresh Token).
* **RF-PAS-03 (Recuperación de Cuenta y Portabilidad de Saldo):**
  * Si el usuario cambia de celular o reinstala la app, ingresa con su mismo número telefónico y el saldo de Puntos BC se restaura de inmediato desde el servidor.
* **RF-PAS-04 (Eliminación de Cuenta):**
  * Mecanismo para solicitar eliminación de cuenta y anonimización de datos personales (cumplimiento normativo de Google Play / Apple App Store).

---

### 2.2. Módulo 2: Monedero de "Puntos BC" y Recargas

* **RF-MON-01 (Moneda Interna y Conversión):**
  * 1 Sol = 10 Puntos BC (1 Punto = S/. 0.10).
  * Tarifa General Adulto: 15 Puntos (S/. 1.50).
  * Tarifa Universitaria: 7 Puntos (S/. 0.70).
* **RF-MON-02 (Recarga Digital Integrada):**
  * Pasarela de pagos local (Yape, Plin, tarjetas de débito/crédito) con acreditación instantánea vía Webhook.
  * Límites operativos de recarga: Mínimo S/. 5.00 (50 puntos), Máximo S/. 100.00 (1000 puntos).
* **RF-MON-03 (Libro Mayor Inmutable / Ledger):**
  * Todo movimiento de puntos (recarga, cobro de viaje, devolución, ajuste administrativo) se almacena en un historial transaccional inmutable con `timestamp`, `id_transaccion`, `bus_id` y saldo resultante.
* **RF-MON-04 (Política Estricta de Saldo):**
  * **Cero saldo negativo.** Si el usuario posee menos puntos que el costo del pasaje, el POS emite tono grave y rechaza el abordaje con alerta: *"Saldo insuficiente: X puntos restantes"*.
* **RF-MON-05 (Reembolso Automático por Avería de Bus):**
  * Si el bus sufre un desperfecto mecánico o accidente durante la ruta y el chofer presiona *"Avería de Unidad"*, el backend reembolsa automáticamente los puntos del pasaje a todos los usuarios que tenían viaje activo en ese bus.

---

### 2.3. Módulo 3: Tarifas Diferenciadas y Acreditaciones

* **RF-TAR-01 (Acreditación de Carnet Universitario vía QR SUNEDU):**
  * El alumno escanea el código QR oficial de SUNEDU impreso en su carnet físico.
  * La app decodifica y extrae: DNI, Universidad, Nombres y Fecha de Caducidad oficial.
  * Captura de fotografía del carnet para auditoría.
* **RF-TAR-02 (Regla de Unicidad de Carnet):**
  * Un mismo carnet universitario (DNI del estudiante) **solo puede estar vinculado a una cuenta activa a la vez** para evitar clonaciones.
* **RF-TAR-03 (Vigencia y Expiración Automática):**
  * La tarifa universitaria tiene vigencia hasta la fecha de caducidad oficial del carnet (máx. 1 año). Al expirar, la cuenta revierte automáticamente a tarifa general si no renueva.
* **RF-TAR-04 (Antifraude por Cooldown de Tarifa Universitaria):**
  * Tras pagar un pasaje universitario (7 puntos), la tarifa universitaria queda bloqueada para la cuenta por **120 segundos (2 minutos)** para evitar pasar el celular a la persona de atrás.
* **RF-TAR-05 (Pago Multipersona con Acompañantes):**
  * El usuario puede agregar pasajes adicionales en la misma transacción (`[+]`), los cuales **siempre se liquidan a tarifa regular de 15 puntos**.
* **RF-TAR-06 (Pasajeros CONADIS):**
  * Exoneración de pasaje (S/. 0.00). El usuario muestra su carnet amarillo físico al conductor, quien registra el abordaje con el botón `[+1 CONADIS]` en la tablet.

---

### 2.4. Módulo 4: Validador en Puerta (POS Maestro en Bus)

* **RF-POS-01 (QR Dinámico por Turno):**
  * El POS muestra un QR de un solo uso: `bc://pay?bus=BUS_01&nonce=UUID_V4&exp=TIMESTAMP`.
  * Auto-refresco de seguridad cada 30 segundos si nadie lo escanea.
  * Al confirmarse el cobro, emite `BEEP` verde y regenera un nuevo QR en menos de 0.5 segundos para la siguiente persona en la fila.
* **RF-POS-02 (Pago Directo con Yape/Plin sin App):**
  * El POS muestra el QR institucional de la empresa por S/. 1.50 y cambia a estado *"Verificando pago... ⏳"*.
  * Confirmación automática vía Webhook bancario en 1 a 2.5 segundos.
  * **Failsafe de 5 segundos:** Si la red bancaria demora más de 5 segundos, la tablet del chofer recibe notificación para validación manual visual del comprobante en el celular del usuario.
* **RF-POS-03 (Telemetría 4G y GPS de Alta Precisión):**
  * Módem 4G LTE y antena GPS conectada a la alimentación del bus (12V/24V). Envío continuo de coordenadas, rumbo y velocidad cada 3 a 5 segundos al backend central.
* **RF-POS-04 (Manejo de Caídas Temporales de Señal 4G):**
  * Si el bus atraviesa una zona ciega de Tacna sin cobertura 4G, el POS muestra un aviso *"Reconectando..."* y la tablet del chofer puede habilitar cobro de contingencia.

---

### 2.5. Módulo 5: Tablet del Conductor (En Cabina)

* **RF-CON-01 (Gestión de Turnos del Chofer):**
  * Inicio de turno mediante PIN / Identificador de conductor.
  * Vinculación de la tablet al `bus_id` asignado para la jornada.
  * Cierre de turno con arqueo automático: desglose de pasajes cobrados por App, Yape directo y CONADIS.
* **RF-CON-02 (Feedback Visual y Sonoro Inmediato):**
  * Muestra tarjetas de gran visibilidad para cada abordaje:
    * 🟢 *"Pasaje Adulto (S/. 1.50)"*
    * 🟡 *"Pasaje Universitario (S/. 0.70)"*
    * 🔴 *"Rechazado: Saldo Insuficiente"*
* **RF-CON-03 (Semáforo de Aforo Estimado - MVP):**
  * Indicador semafórico en tiempo real:
    * 🟢 **Asientos Libres** (< 70% ocupación)
    * 🟡 **Pocos Asientos / De Pie** (70% - 95%)
    * 🔴 **Bus Lleno** (> 95%)
  * Botón de calibración manual rápida: `[Ajustar Bajada]` para paraderos de desembarque masivo.
* **RF-CON-04 (Botón de Emergencia / Avería):**
  * Permite al chofer reportar avería o fin imprevisto de recorrido para notificar a la central y reembolsar puntos a los pasajeros activos.

---

### 2.6. Módulo 6: Geofencing y Desacoplamiento (Backend y App)

* **RF-GEO-01 (Suscripción al Bus en Curso):**
  * Al confirmarse el pago en el POS, el backend asocia la sesión del usuario con el `bus_id` y la ruta activa. La app muestra la trayectoria del bus en tiempo real y paradas restantes.
* **RF-GEO-02 (Algoritmo de Desacoplamiento por Distancia):**
  * La app consulta ubicación cada 45 segundos en segundo plano.
  * Mientras el usuario está a bordo: $\text{Distancia}(\text{Celular}, \text{Bus}) < 25\text{ metros}$.
  * Al bajar en cualquier paradero y alejarse el bus: Si $\text{Distancia} > 150\text{ metros}$, el viaje se marca automáticamente como `FINALIZADO` y se desuscribe la sesión.
* **RF-GEO-03 (Failsafe de Fin de Trayecto):**
  * Si el bus llega al terminal de la línea o el tiempo de viaje supera los 60 minutos, el backend finaliza automáticamente cualquier sesión abierta restante.

---

## 3. Módulos FASE 2 (Post-MVP / Roadmap de Hardware)

* **RF-POST-01 (Concentrador APC Físico con 4 Sensores ToF):**
  * 2 sensores láser ToF (VL53L1X) en techo de puerta delantera y 2 en puerta trasera gestionados por microcontrolador ESP32 con Máquina de Estados Finitos.
* **RF-POST-02 (Detección Física de Evasión - Colados):**
  * Alerta sonora en tablet si alguien cruza el sensor delantero y no registra pago en 4 segundos.
* **RF-POST-03 (Detección de Entrada por Puerta Trasera):**
  * Alerta inmediata si el sensor trasero detecta el patrón inverso de subida.
* **RF-POST-04 (Lector Físico NFC en POS):**
  * Soporte para tarjetas físicas contactless bancarias y tarjetas recargables BC.

