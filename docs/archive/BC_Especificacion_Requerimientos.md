# Proyecto BC (Bus Conectado / Sistema de Buses Automatizado)
## Especificación Detallada de Requerimientos del Sistema (SRS) - Versión 1.4
**Fecha:** Noviembre 2026  
**Ámbito:** Tacna, Perú  
**Alcance:** Separación Formal MVP (Fase 1) vs. Módulos de Hardware Avanzado (Fase 2)

---

## 1. Alcance por Fases del Proyecto

| Subsistema | FASE 1: MVP (Software y POS Base) | FASE 2: Expansión (Hardware APC Físico) |
| :--- | :--- | :--- |
| **App Pasajero** | Modo invitado, mapa en vivo, monedero Puntos BC, QR de pago, carnet SUNEDU, desacoplamiento GPS. | Notificaciones push predictivas, historial avanzado. |
| **POS en Puerta** | Pantalla pasajero, QR dinámico de 1 uso, módem 4G, antena GPS del bus, webhook Yape. | Lector NFC físico activado, interfaz serial con módulo APC. |
| **Tablet Chofer** | Visor de cobro inmediato (verde/amarillo/rojo), botón `[+1 CONADIS]`, ajuste rápido de aforo. | Alerta sonora de colados sincronizada con sensores físicos. |
| **Sensores APC** | **No incluido físicamente.** El aforo se estima por pagos registrados, desacoplamiento y paraderos. | **4 Sensores Láser ToF en techo** (2 delantera, 2 trasera) + microcontrolador ESP32. |

---

## 2. Requerimientos Funcionales - FASE 1 (MVP)

### 2.1. Módulo Pasajero (App Móvil)

#### RF-PAS-01: Modo Invitado (Sin Registro)
* Visualización libre de rutas y buses en movimiento sobre el mapa de Tacna.
* Consulta de paraderos y tiempos estimados de llegada (ETA).
* Indicador semafórico de aforo del bus (🟢 Asientos libres, 🟡 Pocos asientos, 🔴 Bus lleno).
* *Restricción:* Para pagar o recargar puntos se requiere registro telefónico.

#### RF-PAS-02: Registro y Monedero de "Puntos BC"
* Registro rápido mediante número de celular con verificación OTP.
* **Tasa de conversión fija:** S/. 1.00 = 10 Puntos BC (1 Punto = S/. 0.10).
  * Pasaje Adulto / General: 15 Puntos (S/. 1.50).
  * Pasaje Universitario: 7 Puntos (S/. 0.70).
* Recargas integradas vía pasarelas digitales (Yape / Plin / Tarjetas) con acreditación instantánea.
* **Regla estricta:** **Cero saldo negativo.** Si el usuario no tiene los puntos suficientes, el cobro es rechazado en puerta.

#### RF-PAS-03: Tarifa Universitaria (SUNEDU)
* Escaneo del código QR oficial de SUNEDU en el carnet físico del estudiante.
* Extracción automática: DNI, Universidad, Nombres y Fecha de Caducidad oficial.
* Activación de tarifa de 7 puntos con vigencia máxima de 1 año (ligada a la caducidad del carnet). Al vencer, revierte a tarifa general.

#### RF-PAS-04: Antifraude Estudiantil y Acompañantes
* **Cooldown de 2 minutos:** Tras consumir un pasaje universitario, la tarifa reducida queda bloqueada para la cuenta por 120 segundos.
* **Acompañantes (+):** Opción de pagar por acompañantes en la misma transacción; los pasajes extras se liquidan a tarifa general (15 puntos).

#### RF-PAS-05: Desacoplamiento de Coordenadas (Descenso Inteligente sin Agotar Batería)
* Al pagar en el POS, el usuario queda suscrito al `bus_id`.
* La app consulta ubicación cada 45 segundos en segundo plano.
* **Cálculo de Distancia:** Si $\Delta D = \text{Distancia}(\text{Celular}, \text{Bus}) > 150\text{ metros}$, el backend determina que el usuario descendió, finaliza el viaje y desuscribe la sesión automáticamente.

---

### 2.2. Módulo Validador en Puerta (POS Maestro - MVP)

#### RF-POS-01: Generación de QR Dinámico por Turno
* El POS muestra un código QR de un solo uso vinculado a la unidad: `bc://pay?bus=BUS_01&nonce=UUID_V4&exp=TIMESTAMP`.
* Al confirmarse el pago, emite `BEEP` verde durante 800 ms y regenera un nuevo QR de inmediato para el siguiente usuario en la fila.

#### RF-POS-02: Pago Directo con Yape/Plin (Sin App)
* El POS muestra el QR institucional de Yape de la empresa por S/. 1.50.
* Espera la confirmación del webhook bancario (1-2 seg) para emitir el tono de aprobación verde.
* **Failsafe (5 seg):** Si la red bancaria demora más de 5 segundos, la tablet del chofer recibe notificación para validación manual visual del comprobante.

#### RF-POS-03: Telemetría y Nodo GPS
* Módem 4G LTE y antena GPS conectada a la energía del bus (12V/24V). Envío continuo de coordenadas cada 3 a 5 segundos al backend.

---

### 2.3. Módulo Tablet del Conductor (MVP)

#### RF-CON-01: Feedback Visual y Sonoro Inmediato
* Pantalla de alta visibilidad para el chofer que muestra cada ingreso sin necesidad de interactuar:
  * 🟢 *"Pasaje Adulto (S/. 1.50)"*
  * 🟡 *"Pasaje Universitario (S/. 0.70)"*
  * 🔴 *"Rechazado: Saldo Insuficiente"*

#### RF-CON-02: Botón CONADIS (S/. 0.00)
* Botón táctil grande y accesible: `[+1 CONADIS]`. Registra el abordaje gratuito tras revisión visual del carnet amarillo físico e incrementa el contador de aforo.

#### RF-CON-03: Aforo Semafórico Estimado (Fase 1)
* El aforo se calcula en tiempo real en base a:
  $$\text{Aforo} = \sum (\text{Pagos POS} + \text{CONADIS}) - \sum (\text{Descensos por Desacoplamiento})$$
* La tablet incluye un botón rápido de calibración: `[Ajustar Bajada]` para paraderos de desembarque masivo.

---

## 3. Requerimientos Funcionales - FASE 2 (Post-MVP / Roadmap de Hardware)

> [!NOTE]
> Estos requerimientos quedan formalmente especificados para la arquitectura del sistema, pero su implementación física se realizará en la Fase 2 para no demorar el lanzamiento del software.

#### RF-POST-01: Concentrador Físico APC (Automated Passenger Counting)
* Instalación de 4 sensores láser Time-of-Flight (ToF VL53L1X) en techo:
  * 2 en Puerta Delantera (Subida).
  * 2 en Puerta Trasera (Bajada).
* Conectados a un microcontrolador ESP32 que procesa el algoritmo de Máquina de Estados Finitos (FSM) con filtro de anti-congelamiento por tiempo (>2.0 seg).

#### RF-POST-02: Detección Física de Evasión (Colados)
* Si el sensor delantero registra un cruce físico `DOOR_FRONT:ENTER` y no se registra pago en el POS ni pulsación de CONADIS en 4 segundos, emite alerta sonora en la tablet del chofer:  
  ⚠️ *"Pasajero ingresó sin validar pasaje"*.

#### RF-POST-03: Detección de Entrada por Puerta Trasera
* Si el sensor trasero detecta el patrón inverso de subida (`DOOR_REAR:ILLEGAL_ENTER`), notifica inmediatamente al conductor.

#### RF-POST-04: Lector Físico NFC a Bordo
* Activación del lector NFC en el POS para cobro directo con tarjetas contactless bancarias y tarjetas físicas de transporte BC.
