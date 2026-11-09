# Especificación de Arquitectura y Experiencia UI/UX — App Móvil Pasajero
## Sistema BC (Bus Conectado) — Blueprint Nativo (iOS / Android)

> **Archivo de Referencia del Prototipo:** [`mockup/index.html`](file:///Users/aron/githubRepo/sem-bus/mockup/index.html)  
> **Ubicación:** `mockup/APP_PASAJERO.md`  
> **Propósito:** Especificación funcional, ergonómica y técnica exhaustiva para el desarrollo 100% nativo de la **App Pasajero** en **SwiftUI (iOS 17+)** y **Jetpack Compose (Android 14+)**.

---

## 1. Visión General y Objetivos del Producto

La **App Pasajero** del sistema **Bus Conectado (BC)** es la interfaz primaria del ciudadano para el transporte público urbano en Tacna (enfocada inicialmente en la **Línea 10**). Su objetivo principal es erradicar el pago manual con efectivo y resolver la incertidumbre de tiempos de espera mediante:
1. **Cobro Digital Dinámico por QR en Puerta** (< 1 segundo de validación).
2. **Monedero Prepago en Puntos BC** recargable con Yape y Plin (1 PEN = 10 Puntos).
3. **Telemetría y Visualización en Vivo de la Flota** (Línea 10 con múltiples unidades en mapa).
4. **Alertas Inteligentes de Paradero con 2 Temporizadores** (Aviso anticipado + Aviso inminente).
5. **Trazador de Rutas y Asistente al Estilo Google Maps** (Ruta óptima, transbordos, opciones de viaje).
6. **Suscripción y Detección Automática de Unidad** sin alterar artificialmente el aforo físico del bus.

---

## 2. Casos de Uso y Requisitos del Sistema Cubiertos

| Código CU | Nombre del Caso de Uso | Implementación en la App Móvil |
| :--- | :--- | :--- |
| **CU-01** | *Pago de Pasaje con QR Dinámico* | Pantalla de escaneo de cámara, selección de acompañantes, débito en monedero y feedback acústico (880Hz). |
| **CU-05** | *Recarga de Saldo Prepago* | Módulo de monedero con paquetes de S/. 5, S/. 10, S/. 20 y S/. 50 vía Yape / Plin. |
| **CU-06** | *Seguimiento de Viaje en Curso* | Hoja flotante (*In-Trip Sheet*) minimizable en *Explorar*, Dynamic Island y desacoplamiento por geofencing (>150m). |
| **CU-07** | *Consulta de Rutas y Paraderos* | Mapa interactivo de Tacna, marcadores de buses, fichas técnicas y cálculo de ETA del bus más cercano. |
| **CU-08** | *Validación de Identificación Estudiantil* | Aplicación automática de tarifa universitaria (7 pts / S/. 0.70) basada en carné SUNEDU validado. |
| **CU-11** | *Gestión de Perfil y Eliminación de Cuenta* | Menú de perfil, advertencia de liquidación de saldo y baja con período de gracia de 15 días. |

---

## 3. Estructura de Navegación (4 Pestañas Principales)

La interfaz se estructura sobre una barra de navegación fija de **4 pestañas** en la parte inferior, optimizada ergonómicamente para operación con una sola mano:

```
┌─────────────────────────────────────────────────────────────┐
│                      PANTALLA MÓVIL                         │
│                                                             │
│  [ Tab 1: Explorar ]   [ Tab 2: Pagar ]   [ Tab 3: Saldo ]  │
│         (Mapa)              (QR)             (Monedero)     │
│                                                             │
│                      [ Tab 4: Perfil ]                      │
└─────────────────────────────────────────────────────────────┘
```

---

### Pestaña 1: Explorar (Mapa en Vivo, Paraderos y Rutas)

Es la pantalla principal por defecto de la aplicación.

#### A. Barra Superior y Detección Automática
* **Identificador de Línea:** Insignia distintiva de la **Línea 10** (`Cono Norte ➔ Cono Sur`), indicando el número de unidades en circulación en tiempo real.
* **Botón `[📡 Detectar Bus]`:**  
  Permite al usuario forzar la sincronización con el bus si subió a una unidad y la app aún no lo ha detectado por segundo plano. Al presionarlo:
  - Ejecuta una comprobación de telemetría de ruta, velocidad (>10 km/h) y acelerómetro.
  - Si coincide con la posición de un bus de la flota (<25m), vincula el viaje automáticamente, despliega la hoja de viaje (*In-Trip Sheet*) y activa la Dynamic Island.
  - Si no coincide, notifica amablemente que no se detectó un bus en movimiento cercano.

#### B. Buscador Predictivo de Lugares (Estilo Google Maps)
* **Campo de Entrada:** Placeholder dinámico *"Buscar lugar o paradero en Tacna..."*.
* **Lista Desplegable de Sugerencias:**
  - Despliega hitos clave: *Mercado Central*, *Paseo Cívico*, *UNJBG (Campus)*, *Plaza Zela*, *Terminal Terrestre Manuel A. Odría*, etc.
  - Cada fila incluye icono de categoría, nombre del hito, dirección/subtítulo y un **botón circular azul con la flecha de "Ir"**:
    * **Pulsar en el texto/fila:** Centra el mapa en el lugar y suelta un pin de ubicación. Si es un paradero, abre inmediatamente su ficha con los tiempos de llegada y alertas.
    * **Pulsar en el botón circular `[Ir]`:** Abre directamente el **Modo de Trazado de Ruta Automático** con origen en la ubicación actual y destino en dicho punto.

#### C. Visualización de la Flota en Tiempo Real
* En el mapa conviven simultáneamente **4 buses activos** de la Línea 10:
  * **BUS 01** (`Z1A-780`): Chofer Juan Mamani (4.9★), 22/32 pasajeros (68%, Asientos disponibles).
  * **BUS 04** (`Z2B-104`): Chofer Carlos Condori (4.7★), 28/32 pasajeros (87%, Pasajeros de pie).
  * **BUS 07** (`Z3C-550`): Chofer Marco Mamani (4.8★), 14/32 pasajeros (43%, Asientos disponibles).
  * **BUS 12** (`Z4D-990`): Chofer Pedro Flores (4.6★), 31/32 pasajeros (96%, Casi lleno / Rojo).
* **Ficha Técnica del Bus (Al tocar cualquier bus):**
  - **Sin botones manuales de pago ni suscripción** (evita desinformación o suscripciones fraudulentas).
  - Foto del modelo de unidad y placa oficial.
  - Nombre del conductor, calificación y número de brevete.
  - Barra de aforo en vivo semafórica (verde / ámbar / rojo).
  - Próxima parada y tiempo estimado de arribo (ETA).
  - Mensaje explicativo: *"Suscripción Automática activa: Tu app se vinculará a este bus en cuanto abordes o escanees tu QR en puerta"*.

#### D. Paraderos y Sistema de Alertas con 2 Temporizadores
* Paraderos modelados a lo largo de la ruta: **Cono Norte**, **Plaza Zela**, **Paseo Cívico**, **Mercado Central** y **UNJBG (Campus)**.
* Al pulsar un paradero se muestra:
  - Próximos buses en aproximación con sus respectivos ETAs (ej. BUS 01 en ~3 min, BUS 04 en ~10 min).
  - Botón **"🔔 Alerta de Llegada (2 Timers)"** que abre el configurador modal interno:
    * **Temporizador 1 (Alerta Anticipada):** Selector de anticipación en $n = 5$, $10$ o $15$ minutos antes de que el bus alcance el paradero.
    * **Temporizador 2 (Alerta Inminente):** Checkbox para activar notificación y vibración háptica de inminencia (cuando el bus esté a escasos metros o frenando en el paradero).

#### E. Botón Flotante Circular de Direcciones (FAB Inferior Derecho)
* Botón circular azul con flecha de dirección (`corner-up-right`) ubicado sobre la esquina inferior derecha del mapa.
* Abre la pantalla de navegación integral con:
  - **Origen:** Por defecto *"📍 Tu ubicación actual"* (editable).
  - **Destino:** Campo de búsqueda de destino deseado.
  - **Botón de Invertir (⇅):** Intercambia origen y destino instantáneamente.
  - **Selector de Modo de Transporte:** Transporte público (Línea 10) vs A pie.

#### F. Opciones de Ruta y Comparativa de Itinerarios
* El sistema calcula y ofrece múltiples alternativas de desplazamiento:
  - **Opción 1 (Más rápida):** Línea 10 (`BUS 01`) • **12 min** (2 min a pie + 8 min en bus + 2 min a pie) • Próximo bus en ~3 min • Tarifa S/. 0.70 / S/. 1.40.
  - **Opción 2 (Menos concurrida):** Línea 10 (`BUS 04`) • **18 min** • Asientos libres garantizados.
  - **Opción 3 (Caminata directa):** A pie directo • **22 min** • 1.5 km • Cero emisiones.
* Al seleccionar una opción, se despliega el **Itinerario Paso a Paso**:
  1. Caminar hacia el paradero de abordaje sugerido.
  2. Subir al bus indicado de la Línea 10.
  3. Viajar $X$ paradas intermedias.
  4. Descender en el paradero de destino y caminar los metros finales.
* Botón **"Iniciar Ruta en el Mapa"** que traza el vector de recorrido sobre el mapa de Tacna.

#### G. Hoja Flotante de Viaje en Curso (In-Trip Sheet)
* Cuando el usuario está a bordo (por pago QR o detección automática), la pestaña *Explorar* despliega un bottom sheet emergente que no bloquea la navegación general:
  - **Minimizable:** Botón *"Minimizar"* que contrae el viaje a una píldora flotante inferior (`BUS 01 • Próxima: Paseo Cívico ~2 min`), liberando el mapa completo.
  - **Selector de Destino Opcional:** Permite fijar el paradero de desembarque deseado (*Mercado Central*, *UNJBG*, etc.).
  - **Alarma a 400 Metros:** Alarma sonora melódica (C5 ➔ E5 ➔ G5 ➔ C6) que avisa con 400 metros de anticipación antes de la parada fijada.
  - **Descenso por Geofencing:** Botón de simulación de bajada que ejecuta el desacoplamiento al alejarse >150 metros del bus.

---

### Pestaña 2: Pagar QR (Escáner en Puerta)

* **Visor de Cámara Nativo:**  
  Capa de video optimizada con visor reticular y animación de barrido láser para enfocar la pantalla del módulo validador POS en la puerta delantera del bus.
* **Badge de Tarifa Activa:**  
  Muestra el beneficio del usuario (ej. `🎓 Universitario: 7 pts / S/. 0.70`).
* **Selector de Acompañantes (`[+]` / `[-]`):**  
  Implementa la regla de negocio **RN-07**:
  - Máximo 4 acompañantes simultáneos.
  - El titular abona su tarifa preferencial (7 pts); cada acompañante abona tarifa general adulto (+15 pts / S/. 1.50).
  - Cálculo dinámico en tiempo real del débito total en Puntos BC y PEN.
* **Feedback Inmediato de Cobro:**  
  Al validar el código QR dinámico (30s TTL):
  - Emite el tono acústico verde de 880Hz (800ms).
  - Genera vibración háptica de éxito (`UINotificationFeedbackGenerator.success`).
  - Descuenta los puntos de forma atómica.
  - **Suscribe automáticamente** al usuario a la unidad e inicia la Live Activity en la Dynamic Island.

---

### Pestaña 3: Monedero (Prepago y Beneficios)

* **Tarjeta de Saldo Principal:**  
  Visualización en tipografía gigante del saldo en **Puntos BC** y su conversión exacta a Soles (ej. `85 Puntos BC = S/. 8.50`).
* **Recarga Instantánea con Billeteras Móviles:**  
  Cuadrícula táctil para recargas rápidas con Yape y Plin:
  - `+S/. 5` (+50 pts)
  - `+S/. 10` (+100 pts)
  - `+S/. 20` (+200 pts)
  - `+S/. 50` (+500 pts)
  - Sonido de confirmación de monedas (987Hz ➔ 1318Hz).
* **Tarjeta de Identificación Estudiantil (CU-08):**  
  Muestra el estado de la validación del Carné Universitario emitido por SUNEDU, fecha de vencimiento y vigencia de la prórroga anual configurada en el backoffice.

---

### Pestaña 4: Perfil y Ajustes

* **Datos de Identidad:** Nombre del titular, número telefónico verificado (`+51 952 ••• 819`) y badge de *"Perfil Verificado"*.
* **Accesos Rápidos:** Historial de viajes, configuración de notificaciones, términos de servicio y políticas de privacidad.
* **Baja Definitiva de Cuenta (CU-11):**  
  - Botón claramente visible pero protegido con confirmación.
  - Modal interno que informa el saldo actual no reembolsable en Puntos BC.
  - Notifica el **período de gracia legal de 15 días** durante el cual el usuario puede revocar la baja volviendo a iniciar sesión con su número de teléfono.

---

## 4. Reglas de Negocio (RN) Aplicadas en la App

| Regla | Descripción Técnica |
| :--- | :--- |
| **RN-01** | **Caducidad de QR Dinámico:** El validador POS rota su código QR cada 30 segundos; la app rechaza códigos con timestamp mayor a 30s para evitar capturas de pantalla o clonaciones. |
| **RN-02** | **Paridad Prepago Invariable:** 1 Sol Peruano (PEN) equivale estrictamente a 10 Puntos BC. |
| **RN-04** | **Transacciones Atómicas:** Toda validación de viaje se procesa como transacción ACID en backend; no existe cobro diferido ni riesgo de doble cobro. |
| **RN-07** | **Acompañantes con Tarifa Adulto:** El beneficio universitario o escolar es personal e intransferible. Todo acompañante añadido en la app abona la tarifa general regular. |
| **RN-09** | **Desacoplamiento Automático por Geofencing:** Cuando el GPS del teléfono registre una distancia mayor a 150 metros respecto al bus durante 30 segundos continuos, el viaje se cierra automáticamente. |
| **RN-Aforo** | **Invariabilidad de Aforo por Suscripción:** Suscribirse o seguir a un bus manualmente o por proximidad **NO altera el aforo** de la unidad. El semáforo y contador de capacidad solo se incrementan tras registrar un pago financiero real (App QR, validador POS o registro de conductor). |

---

## 5. Mapeo Arquitectónico a Código Nativo

### 🍎 En iOS (SwiftUI + iOS 17+)

| Componente del Mockup | Componente Nativo SwiftUI | Framework / API de Apple |
| :--- | :--- | :--- |
| Navegación de 4 Pestañas | `TabView(selection: $selectedTab)` | `SwiftUI` |
| Mapa Vectorial con Buses y Paraderos | `Map(position: $cameraPosition)` con `Annotation` | `MapKit` |
| Hoja Flotante de Viaje Minimizable | `.sheet(isPresented:)` con `.presentationDetents([.fraction(0.12), .fraction(0.70)])` | `SwiftUI` |
| Dynamic Island y Pantalla Bloqueada | `Activity<TripActivityAttributes>` (Live Activity) | `ActivityKit` / `WidgetKit` |
| Alertas de 2 Temporizadores | `UNUserNotificationCenter` con `UNLocationNotificationTrigger` | `UserNotifications` |
| Escáner de Código QR en Puerta | `AVCaptureSession` con `AVCaptureMetadataOutput` | `AVFoundation` |
| Feedback Táctil y Háptico | `UIImpactFeedbackGenerator(.medium)` y `UINotificationFeedbackGenerator` | `UIKit` / CoreHaptics |
| Almacenamiento Seguro de Credenciales | Bóveda de contraseñas con cifrado por hardware | **Apple Keychain Services** |

### 🤖 En Android (Jetpack Compose + Android 14+)

| Componente del Mockup | Componente Jetpack Compose | Especificación Android |
| :--- | :--- | :--- |
| Navegación Inferior (4 Tabs) | `NavigationBar` con `NavigationBarItem` | `androidx.compose.material3` |
| Mapa Interactivo | `GoogleMap` con marcadores personalizados `MarkerComposable` | `com.google.maps.android:maps-compose` |
| Hoja Flotante de Viaje | `ModalBottomSheet` o `BottomSheetScaffold` con `rememberBottomSheetScaffoldState` | Material 3 Sheets |
| Notificación de Viaje Activo | `NotificationCompat.Builder` en `ForegroundService` con `CATEGORY_NAVIGATION` | Android Notifications |
| Alertas de Paradero Geofencing | `GeofencingClient` con `Geofence.Builder` y `GEOFENCE_TRANSITION_ENTER` | `com.google.android.gms:play-services-location` |
| Escáner QR | `PreviewView` con analizador de imágenes `BarcodeScanning` | **Google ML Kit Barcode Scanning** |
| Almacenamiento Seguro | Bóveda de tokens con chip de seguridad | **Android Jetpack Security (EncryptedSharedPreferences)** |

---

## 6. Comportamiento en Segundo Plano y Notificaciones

1. **Alerta Previa (Temporizador 1 - 5/10/15 min):**  
   * El cálculo de aproximación se ejecuta en el backend mediante Redis Geo y telemetría de ruta.
   * Cuando el bus activo cruza el umbral temporal ($n$ minutos), el servidor despacha un mensaje **Push de Alta Prioridad** (APNs en iOS / FCM en Android), despertando la app para sonar y mostrar el aviso sin consumir batería continua en el móvil.
2. **Alerta Inminente (Temporizador 2 - A segundos de la parada):**  
   * Se registra una geocerca circular (*Geofence*) de 80 metros alrededor del paradero en el servicio de ubicación del sistema operativo (`CoreLocation` / `Play Services Location`).
   * Al detectarse la proximidad del bus, se activa la segunda alerta sonora con vibración distintiva.
3. **Live Activity (Dynamic Island en iOS):**  
   * Mantiene el estado del viaje visible en todo momento mientras el usuario utiliza otras aplicaciones:
     - Nombre de la línea y placa (`L10 • BUS 01`).
     - Próxima parada y tiempo estimado.
     - Indicador visual de parada fijada de desembarque.

---

## 7. Instrucciones para la Ejecución y Validación del Mockup

1. Abre el archivo [`mockup/index.html`](file:///Users/aron/githubRepo/sem-bus/mockup/index.html) con tu navegador de preferencia.
2. Selecciona la pestaña superior **"App Pasajero (iOS)"**.
3. **Prueba los flujos:**
   - **Flujo A (Exploración):** Toca un bus para ver su ficha; pulsa un paradero para programar una alerta con 2 temporizadores.
   - **Flujo B (Búsqueda y Ruta):** Escribe *"Mercado Central"* en el buscador y pulsa el botón circular `[Ir]` para ver las 3 opciones de viaje con sus pasos.
   - **Flujo C (Pago y Viaje):** Ve a *"Pagar QR"*, añade acompañantes y pulsa *"Pagar"*. Verás la deducción en el monedero y la activación automática de la hoja de viaje.
   - **Flujo D (Descenso):** En la hoja de viaje, pulsa *"Simular Descenso (>150m)"* para comprobar el cierre automático de la sesión.

