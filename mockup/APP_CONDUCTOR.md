# Especificación de Arquitectura y Experiencia UI/UX — App Tablet Conductor
## Sistema BC (Bus Conectado) — Blueprint Nativo (Android Tablet)

> **Archivo de Referencia del Prototipo:** [`mockup/index.html`](file:///Users/aron/githubRepo/sem-bus/mockup/index.html) (Contenedor `#view-driver`)  
> **Ubicación:** `mockup/APP_CONDUCTOR.md`  
> **Versión:** 1.0 (Noviembre 2026)  
> **Dispositivo Objetivo:** Tablet Android 10" (Landscape, 1280×800 px o superior) fija en cabina de bus.

---

## 1. Resumen Ejecutivo y Propósito del Dispositivo

La **App Conductor** es la terminal de cabina montada sobre un soporte antivibración en el tablero del chofer. Opera en modo quiosco (*kiosk mode*) y cumple tres objetivos esenciales:

1. **Monitoreo de Cobro en Tiempo Real:** Proporcionar confirmación visual y acústica periférica instantánea (<0.5 segundos) de cada pasaje validado en la puerta de abordaje sin obligar al chofer a desviar la vista del tráfico.
2. **Control de Aforo y Paraderos:** Visualizar el porcentaje de ocupación de la unidad con código semafórico dinámico y alertar la proximidad del siguiente paradero.
3. **Registro Exonerado y Contingencias:** Botones táctiles de gran dimensión para registro de pasajeros CONADIS (Ley 29973), calibración de bajada en paraderos de desembarque masivo y declaración de avería mecánica.

---

## 2. Especificación Técnica de Pantalla y Ergonomía

| Parámetro | Especificación | Justificación Ergonómica |
| :--- | :--- | :--- |
| **Orientación** | Paisaje (Landscape) exclusivo | Amplitud horizontal para tablero vehicular. |
| **Resolución Base** | 1280 × 800 dp (Aspecto 16:10) | Estándar en tablets industriales y comerciales de 10 pulgadas. |
| **Modo Visual** | Dark Theme de alto contraste (Slate-950 base) | Evita deslumbramientos nocturnos y fatiga visual en turnos de 8 horas. |
| **Zona Táctil Mínima** | 64 × 64 dp (Botones principales: 80+ dp) | Permite pulsaciones certeras incluso con el bus en movimiento y vibración. |
| **Tipografía** | Numérica tabular monoespaciada (`JetBrains Mono` / `Roboto Mono`) | Legibilidad inmediata de montos y porcentajes a 80 cm de distancia ocular. |

---

## 3. Arquitectura de Pantallas y Flujos de Operación

```
┌────────────────────────────────────────────────────────┐
│                   INICIO DE TURNO                      │
│     PIN Conductor (4 dígitos) ➔ Selección de Bus       │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│             PANTALLA PRINCIPAL DE CABINA               │
│ ┌───────────────────────┬────────────────────────────┐ │
│ │  PANEL IZQUIERDO      │   PANEL DERECHO            │ │
│ │  - Tarjeta Cobro Pop  │   - Semáforo de Aforo      │ │
│ │  - Feed de Abordaje   │   - Acciones Rápidas:      │ │
│ │  - Datos de Turno     │     [+1 CONADIS]           │ │
│ │                       │     [Ajustar Bajada]       │ │
│ │                       │     [Avería de Unidad]     │ │
│ │                       │     [Cerrar Turno]         │ │
│ └───────────────────────┴────────────────────────────┘ │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│                   CIERRE DE TURNO                      │
│        Resumen de Arqueo ➔ Confirmación y Cierre       │
└────────────────────────────────────────────────────────┘
```

---

## 4. Descripción Detallada de Módulos de Cabina

### 4.1. Módulo de Confirmación de Cobro (HUD Periférico)
Ubicado en la parte superior izquierda, muestra una tarjeta de alto impacto visual con auto-ocultamiento progresivo:
* **Tarjeta de Validación Instantánea:**
  - 🟢 **Tarifa General (S/. 1.50):** Borde y fondo esmeralda brillante.
  - 🟡 **Tarifa Universitaria SUNEDU (S/. 0.70):** Borde y acento ámbar con etiqueta `"UNIV"`.
  - 🔵 **Pase Libre CONADIS (S/. 0.00):** Acento celeste con insignia `"CONADIS"`.
  - 🔴 **Rechazo / Saldo Insuficiente:** Tono grave y destello carmesí `"RECHAZADO"`.
* **Barra de Tiempo de Expiración:** Barra de progreso lineal animada (3 segundos) que se vacía suavemente hasta el próximo abordaje.
* **Feed Histórico:** Lista desplazable con los últimos 15 abordajes indicando timestamp, nombre del pasajero, tipo de tarifa y medio de pago (App QR / Yape POS).

### 4.2. Módulo de Aforo y Semáforo de Capacidad
* **Indicador Porcentual:** Cifra destacada (ej. `68%`) con conteo de pasajeros en cabina (`22 / 32 Pasajeros`).
* **Estados Semafóricos:**
  - 🟢 **Asientos Disponibles:** `< 70%` de ocupación.
  - 🟡 **Pocos Asientos / De Pie:** `70% - 95%` de ocupación.
  - 🔴 **Capacidad Completa:** `> 95%` de ocupación.
* **Sincronización:** El validador POS en puerta y la tablet se sincronizan mediante WebSockets locales o vía broker MQTT con latencia inferior a 200 ms.

### 4.3. Botones de Acción Rápida (Cabina)
* **`[+1 CONADIS]` (Ámbar / Oro):**  
  Pulsador de un toque para registrar el abordaje de personas con discapacidad severa acreditadas con carné CONADIS físico. Incrementa el aforo sin generar cargo financiero.
* **`[Ajustar Bajada -3]` (Azul Pizarra):**  
  Permite al conductor restar ocupantes de forma rápida en paraderos masivos (ej. Mercado Central) si no se cuenta con sensor APC en la puerta posterior.
* **`[Avería de Unidad]` (Rojo Peligro):**  
  Requiere confirmación de 2 pasos. Al activarse:
  1. Notifica a la central de monitoreo de flota.
  2. Dispara el reembolso atómico automático de puntos a todos los pasajeros con viaje activo en la unidad.
  3. Muestra el estado `"BUS FUERA DE SERVICIO"` en la app de pasajeros.

### 4.4. Cierre de Turno y Arqueo Digital
Al presionar `[Cerrar Turno]`:
* Se presenta un diálogo modal con el resumen auditado de la jornada:
  - Pasajes cobrados por App BC (unidades y recaudación en PEN).
  - Pasajes cobrados por Yape directo en POS.
  - Pasajeros CONADIS registrados.
  - Kilometraje y paraderos recorridos.
* Requiere reingreso de PIN para firmar el cuadre de caja y desvincular la tablet de la unidad vehicular.

---

## 5. Mapeo a Componentes Nativos (Android Jetpack Compose)

| Componente del Mockup | Componente Nativo Compose | Librería / API Android |
| :--- | :--- | :--- |
| Contenedor Principal Landscape | `Scaffold` con layout horizontal | `androidx.compose.material3` |
| Tarjeta HUD de Cobro | `AnimatedVisibility` con `Card` + `BorderStroke` | Compose Animation |
| Barra de Tiempo | `LinearProgressIndicator` con tween animation | Compose Material3 |
| Feed de Abordajes | `LazyColumn(reverseLayout = false)` | Compose Foundation |
| Semáforo de Aforo | `CircularProgressIndicator` o `Box` con canvas circular | Compose Graphics |
| Botón de Emergencia / Avería | `Button(colors = ButtonDefaults.buttonColors(containerColor = Red))` | Material3 |
| Persistencia y Conexión POS | Service con Foreground Notification + WebSocket Client | Ktor Client / OkHttp WS |

---

## 6. Casos de Uso SWEBOK Mapeados

* **CU-04:** *Operación de Turno Conductor en Tablet de Cabina*
* **CU-01:** *Abordaje y Pago de Pasaje con QR (Recepción en cabina)*
* **CU-02:** *Pago Directo con Yape sin App (Failsafe y verificación en cabina)*
* **CU-06:** *Descenso y Desacoplamiento (Ajuste manual de aforo)*
* **CU-10:** *Vinculación Segura de Hardware (Tablet ➔ Unidad de Bus)*

