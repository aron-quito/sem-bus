# Especificación de Arquitectura y Experiencia UI/UX — App Móvil Pasajero
## Sistema BC (Bus Conectado) — Blueprint Nativo (iOS / Android)

> **Archivo de Referencia del Prototipo:** [`mockup/index.html`](file:///Users/aron/githubRepo/sem-bus/mockup/index.html)  
> **Ubicación:** `mockup/APP_PASAJERO.md`  
> **Viewport Físico de Referencia:** **iPhone 16** (393 pt × 852 pt @3x, radio de esquina 55px, Dynamic Island nativa).  
> **Propósito:** Especificación funcional, ergonómica y técnica exhaustiva para el desarrollo 100% nativo de la **App Pasajero** en **SwiftUI (iOS 18+)** y **Jetpack Compose (Android 15+)**.

---

## 1. Visión General y Objetivos del Producto

La **App Pasajero** del sistema **Bus Conectado (BC)** es la interfaz primaria del ciudadano para el transporte público urbano en Tacna (enfocada inicialmente en la **Línea 10**). Su objetivo principal es erradicar el pago manual con efectivo y resolver la incertidumbre de tiempos de espera mediante:
1. **Cobro Digital Dinámico por QR en Puerta** (< 1 segundo de validación).
2. **Monedero Prepago en Puntos BC** recargable con Yape y Plin (1 PEN = 10 Puntos).
3. **Telemetría y Visualización en Vivo de la Flota** (Línea 10 con exactamente 2 unidades activas: `BUS 01` y `BUS 07`).
4. **Red de Paraderos Oficiales Optimizada** (3 paraderos clave: **Plaza Zela**, **P. Mercado**, **P. UNJBG**).
5. **Navegación Integral Pantalla Completa Estilo Google Maps** con hoja interactiva de 3 niveles de estiramiento (*Compacto*, *Detalle Intermedio* y *Todas las Opciones*).
6. **Alertas Inteligentes de Paradero con 2 Temporizadores** (Aviso anticipado + Aviso inminente).
7. **Suscripción y Detección Automática de Unidad** sin alterar artificialmente el aforo físico del bus.

---

## 2. Especificaciones de Pantalla — iPhone 16

| Parámetro de Diseño | Valor Estándar iPhone 16 | Implementación en Prototipo |
| :--- | :--- | :--- |
| **Ancho Lógico (Width)** | **393 pt** | `width: 393px;` en contenedor `.iphone-frame` |
| **Alto Lógico (Height)** | **852 pt** | `height: 852px;` en contenedor `.iphone-frame` |
| **Radio de Borde (Corner Radius)** | **55 pt** | `border-radius: 55px;` |
| **Densidad de Píxeles** | `@3x` (2556 × 1179 px) | Renderizado Retina en navegadores web |
| **Dynamic Island** | 125 px ancho × 35 px alto | Centrada a 11px de margen superior |
| **Home Indicator Safe Area** | Altura reservada 34 pt | Barra de pestañas inferior de `84px` con padding bottom `pb-6` |

---

## 3. Casos de Uso y Requisitos del Sistema Cubiertos

| Código CU | Nombre del Caso de Uso | Implementación en la App Móvil |
| :--- | :--- | :--- |
| **CU-01** | *Pago de Pasaje con QR Dinámico* | Pantalla de escaneo de cámara, selección de acompañantes, débito en monedero y feedback acústico (880Hz). |
| **CU-05** | *Recarga de Saldo Prepago* | Módulo de monedero con paquetes de S/. 5, S/. 10, S/. 20 y S/. 50 vía Yape / Plin. |
| **CU-06** | *Seguimiento de Viaje en Curso* | Hoja flotante (*In-Trip Sheet*) minimizable en *Explorar*, Dynamic Island y desacoplamiento por geofencing (>150m). |
| **CU-07** | *Consulta de Rutas y Paraderos* | Mapa interactivo de Tacna, marcadores de 2 buses, 3 paraderos oficiales y cálculo de ETA del bus más cercano. |
| **CU-08** | *Validación de Identificación Estudiantil* | Aplicación automática de tarifa universitaria (7 pts / S/. 0.70) basada en carné SUNEDU validado. |
| **CU-11** | *Gestión de Perfil y Eliminación de Cuenta* | Menú de perfil, advertencia de liquidación de saldo y baja con período de gracia de 15 días. |

---

## 4. Estructura de Navegación (4 Pestañas Principales + Perfil Superior)

La interfaz se estructura sobre una barra de navegación fija de **4 pestañas** en la parte inferior, con altura de `84px` y espacio libre para el *Home Indicator* de iOS, junto al **Perfil de Usuario estilo Google** reubicado en la barra de búsqueda superior:

```
┌─────────────────────────────────────────────────────────────┐
│                      PANTALLA MÓVIL (393 × 852)             │
│  [🔍 Buscar paradero o línea...       🎤] [👤 Perfil (A)]   │
│                                                             │
│  [ Tab 1: Explorar ]   [ Tab 2: Líneas ]   [ Tab 3: Pagar QR ]
│      (Icono Globo)        (Icono Bus)         (Icono Scan)   │
│                                                             │
│                      [ Tab 4: Monedero ]                    │
│                       (Icono Wallet)                        │
└─────────────────────────────────────────────────────────────┘
```

---

### Pestaña 1: Explorar (Mapa en Vivo, Paraderos y Rutas)

Es la pantalla principal por defecto de la aplicación.

#### A. Barra Superior con Perfil Google-Style y Filtros de Categoría
* **Buscador en Píldora Superior:** Campo de búsqueda redondeado con icono de marcador azul en círculo a la izquierda, placeholder *"Buscar paradero o línea en Tacna..."*, icono de micrófono y **avatar circular de Perfil ("A") a la extrema derecha**.
* **Pop-up de Perfil estilo Google (`#modal-google-profile`):**
  - Al pulsar el avatar circular `[A]` en el buscador, se despliega un diálogo centrado/flotante con diseño inspirado en la cuenta de Google / Google Maps.
  - **Identidad del Usuario:** Avatar con degradado, nombre *"Aron Mamani Quispe"*, correo `aron.mamani@unjbg.edu.pe`, y badge de cuenta universitaria verificada.
  - **Resumen Rápido de Monedero:** Saldo disponible (85 pts / S/. 8.50) con botón directo *"Ver Monedero"*.
  - **Opciones de Cuenta:**
    - `Configuraciones` (*con etiqueta "Próximamente", apartado reservado para futuras versiones sin modificar el alcance actual*).
    - `Líneas y Paraderos` (acceso directo a rutas guardadas).
    - `Ayuda y soporte` (centro de reportes y retroalimentación).
    - `Gestionar cuenta` y `Cerrar sesión`.
* **Fila de Filtros Rápidos (Todo, Rutas, Paraderos):**
  - **Todo (Marcado por default):** Muestra simultáneamente la ruta, los 2 buses en vivo y los 3 paraderos.
  - **Rutas:** Filtra el mapa enfocando la ruta y los buses activos (`BUS 01` y `BUS 07`).
  - **Paraderos:** Filtra el mapa enfocando exclusivamente los 3 paraderos oficiales de la Línea 10.
* **Botón `[📡 Wifi / Detectar Bus]`:** Ubicado en la esquina superior derecha del mapa para forzar la sincronización acústica y telemétrica si la app aún no detectó el abordaje.

#### B. Buscador Predictivo con Menú Sólido (Cero Transparencias)
* **Menú Desplegable Opaco:** Caja sólida `#0F172A` con borde reforzado `z-50`, eliminando el solapamiento o transparencia con los elementos y calles del mapa.
* Cada fila incluye tarjeta individual destacada con icono, nombre, dirección/subtítulo y el **botón circular azul con la flecha de "Ir"**:
  * **Pulsar en el texto/fila:** Centra el mapa en el lugar y suelta un pin de ubicación. Si es un paradero, abre inmediatamente su ficha con los tiempos de llegada y alertas.
  * **Pulsar en el botón circular `[Ir]`:** Abre directamente el **Modo Pantalla Completa Google Maps** con origen en *"Tu ubicación"* y destino fijado.

#### C. Visualización de la Flota en Tiempo Real (Exactamente 2 Unidades)
* En el mapa conviven exactamente **2 buses activos** de la Línea 10:
  * **BUS 01** (`Z1A-780`): Chofer Juan Mamani (4.9★), 22/32 pasajeros (68%, Asientos disponibles).
  * **BUS 07** (`Z3C-550`): Chofer Marco Mamani (4.8★), 14/32 pasajeros (43%, Asientos disponibles).
* **Ficha Técnica del Bus (Al tocar cualquier bus):**
  - **Sin botones manuales de pago ni suscripción** (evita desinformación o suscripciones fraudulentas).
  - Foto del modelo de unidad y placa oficial.
  - Nombre del conductor, calificación y número de brevete.
  - Barra de aforo en vivo semafórica (verde / ámbar / rojo).
  - Próxima parada y tiempo estimado de arribo (ETA).
  - Mensaje explicativo: *"Suscripción Automática activa: Tu app se vinculará a este bus en cuanto abordes o escanees tu QR en puerta"*.

#### D. Red Oficial de 3 Paraderos y Sistema de Alertas con 2 Temporizadores
* Paraderos modelados estratégicamente en Tacna:
  1. **Plaza Zela** (`Calle Zela • Conexión Centro Histórico`)
  2. **P. Mercado** (`Av. Bolognesi • Conexión Zona Comercial`)
  3. **P. UNJBG** (`Av. Miraflores • Campus Universitario Los Pabellones`)
* Al pulsar un paradero se muestra:
  - Próximos buses en aproximación con sus respectivos ETAs (ej. BUS 01 en ~3 min, BUS 07 en ~11 min).
  - Botón **"🔔 Alerta de Llegada (2 Timers)"** que abre el configurador modal interno:
    * **Temporizador 1 (Alerta Anticipada):** Selector de anticipación en $n = 5$, $10$ o $15$ minutos antes de que el bus alcance el paradero.
    * **Temporizador 2 (Alerta Inminente):** Checkbox para activar notificación y vibración háptica de inminencia (cuando el bus esté a escasos metros o frenando en el paradero).

#### E. Escenario Pantalla Completa Estilo Google Maps ("Cómo Llegar")
Al tocar el botón de dirección (FAB cian `[↱]` o el botón circular `[Ir]` en cualquier búsqueda), la app despliega un escenario que **ocupa el 100% de la pantalla del móvil**:
* **Cabecera Nativa de Ruteo:**
  - Botón de retroceso `[<]` integrado en la fila de origen/destino (sin solapamiento con los puntos guía).
  - Puntos de parada con conexión vertical: Origen (*Tu ubicación*) y Destino dinámico (*Plaza Zela*, *P. UNJBG*, *P. Mercado* o *Mercadillo Bolognesi*).
  - Botón de inversión de sentido `[⇅]` y opciones `[...]`.
  - Marco superior opaco `bg-slate-950` con desenfoque de fondo que garantiza que la barra de estado y la Dynamic Island mantengan fondo oscuro continuo sin que las calles o rutas se filtren por detrás.
  - Píldora multimodal flotante que resume el trayecto (ej. `🚶‍♂️ 2m ➔ 🚌 BUS 01 (14m) ➔ 16 min · S/. 0.70` o `🚶‍♂️ 2 min a pie · 180 m · Gratis`).

* **Casos de Ruteo Dinámico según el Destino Seleccionado:**
  1. **Destino: Plaza Zela (Paradero cercano):**
     - Al ser el paradero más próximo al origen, la mejor y única opción es **caminar directamente** hacia dicho paradero.
     - En el mapa se dibuja únicamente el trayecto a pie (punteado cian, 180 metros) con Pin Rojo de destino final en Plaza Zela. No se traza bus ni se muestran unidades aproximándose.
     - Resumen: **2 min • 180 m • Sin costo (Gratis)**.
  2. **Destino: P. UNJBG (Campus Universitario):**
     - Origen camina 2 min hasta Plaza Zela, aborda `BUS 01` (tarifa S/. 0.70).
     - El bus recorre la Línea 10 pasando por *P. Mercado* (marcado como parada intermedia) y continúa hacia el sur hasta **P. UNJBG**.
     - En el mapa se destaca el aviso *"Bajar aquí (P. UNJBG)"* con Pin Rojo de destino en el paradero universitario.
     - Resumen: **16 min • 3.2 km • Tarifa Universitaria S/. 0.70**.
  3. **Destino: P. Mercado / Mercadillo Bolognesi:**
     - Camina a Plaza Zela, toma `BUS 01` por 8 min, baja en *P. Mercado* (y si el destino es el mercadillo, camina 1 min adicional a pie).
     - Resumen: **10 a 12 min • 1.2 a 1.4 km • S/. 0.70**.

* **Hoja Inferior Interactiva de 3 Niveles (Bottom Sheet Snap States):**
  1. **Nivel 1: Compacto (Peek, ~185px):**
     - Muestra el tiempo principal (`12 min · 1.4 km` o `2 min · 180 m`), botón para compartir, botón de cerrar `[✕]`, botón principal verde `[Iniciar]` y botón de `[ETA]`.
  2. **Nivel 2: Primer Estiramiento / Detalle (Medium, ~360px):**
     - Detalle de hora de llegada estimada, ahorro de combustible o impacto ecológico, tarjeta informativa de la unidad próxima y desglose de pasos legibles.
  3. **Nivel 3: Estiramiento Completo (Full, 88% de pantalla):**
     - Despliega el catálogo completo con **todas las formas de llegar al destino**:
       - *Opción 1 (Recomendada):* **BUS 01 (Línea 10)** o **Caminata Directa** según el destino.
       - *Opción 2:* **BUS 07 (Línea 10)** con aforo menor garantizado.
       - Filtros rápidos (*Más rápida*, *Menos trasbordos*, *Asientos libres*).
       - Tarjeta con foto del destino y botón inferior fijado `[Iniciar]`.

* **Comportamiento del Botón "Iniciar" (Guía de Ruta en Mapa Principal):**
  - Al presionar **"Iniciar"** en cualquier nivel de la hoja de ruteo:
    1. Cierra el escenario completo de Google Maps y regresa a la pantalla principal (*Explorar*).
    2. **Marca y resalta la ruta trazada sobre el mapa principal:** Muestra la línea de caminata (cian punteado), el tramo de bus (azul/cian brillante continuo) y el **Pin Rojo de Destino** (`P. UNJBG`, `Plaza Zela` o `Mercadillo Bolognesi`).
    3. **Pop-up Circular Verde (Timer en la esquina superior izquierda):** Despliega un widget circular verde con pulso luminoso que muestra un **Timer regresivo en vivo** (`02:48`) del tiempo estimado para la llegada del próximo bus al paradero de abordaje.
    4. **Botón Circular Rojo de Cancelación `[✕]`:** Ubicado directamente debajo del timer verde. Al pulsarlo, abre un modal de confirmación:
       * *¿Deseas cancelar la dirección de ruta establecida por el usuario y la guía?*
       * Si se confirma, cancela la guía, detiene el timer, retira el trazado de la ruta del mapa y restaura la interfaz inicial limpia.
    5. **Barra Inferior Activa:** Los botones inferiores (*Explorar*, *Líneas*, *Pagar QR*, *Perfil*) permanecen 100% operativos para que el usuario pueda pagar con QR en puerta o revisar líneas cuando el bus arribe.

* **Comportamiento del Botón "Alerta de Llegada":**
  - Al pulsar **"Alerta de llegada"** en la ficha de un paradero (o desde su configurador):
    - Cierra la ficha del paradero.
    - Despliega **únicamente el pop-up circular verde con el Timer** en la esquina superior izquierda (sin marcar ruta ni mostrar el botón rojo de cancelación), manteniendo el mapa limpio con el recordatorio del bus aproximándose.

#### F. Hoja Flotante de Viaje en Curso (In-Trip Sheet)
* Cuando el usuario está a bordo (por pago QR o detección automática), la pestaña *Explorar* despliega un bottom sheet emergente que no bloquea la navegación general:
  - **Minimizable:** Botón *"Minimizar"* que contrae el viaje a una píldora flotante inferior (`BUS 01 • Próxima: P. Mercado ~2 min`), liberando el mapa completo.
  - **Selector de Destino Opcional:** Permite fijar el paradero de desembarque deseado (*P. Mercado*, *P. UNJBG*, etc.).
  - **Alarma a 400 Metros:** Alarma sonora melódica (C5 ➔ E5 ➔ G5 ➔ C6) que avisa con 400 metros de anticipación antes de la parada fijada.
  - **Descenso por Geofencing:** Botón de simulación de bajada que ejecuta el desacoplamiento al alejarse >150 metros del bus.
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

### Pestaña 2: Líneas (Catálogo de Rutas de Tacna)

* **Detalle Operativo de la Línea 10:** Recorrido oficial Cono Norte ➔ Cono Sur, paraderos oficiales (Plaza Zela, P. Mercado, P. UNJBG), frecuencias estimadas y unidades en circulación (`BUS 01` y `BUS 07`).
* **Selector de Dirección (Ida / Vuelta):** Alternancia entre sentido Subida y Bajada.
* **Acceso Directo al Mapa:** Botón para proyectar la traza completa de la línea en la pantalla principal.

---

### Pestaña 3: Pagar QR (Escáner en Puerta)

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

### Pestaña 4: Monedero (Prepago, Historial de Viajes y Beneficios)

* **Tarjeta de Saldo Principal:**  
  Visualización en tipografía gigante del saldo en **Puntos BC** y su conversión exacta a Soles (ej. `85 Puntos BC = S/. 8.50`).
* **Recarga Instantánea con Billeteras Móviles (Yape / Plin):**  
  Cuadrícula táctil para recargas rápidas con Yape y Plin:
  - `+S/. 5` (+50 pts)
  - `+S/. 10` (+100 pts)
  - `+S/. 20` (+200 pts)
  - `+S/. 50` (+500 pts)
  - Sonido de confirmación de monedas (987Hz ➔ 1318Hz).
* **Tarjeta de Identificación Estudiantil (CU-08):**  
  Muestra el estado de la validación del Carné Universitario emitido por SUNEDU, fecha de vencimiento y vigencia de la prórroga anual configurada en el backoffice.
* **Historial de Viajes y Movimientos (CU-10):**
  - **Filtros Interactivos:** Segmentación rápida por chips: *"Todos (4)"*, *"Viajes (3)"*, y *"Recargas (1)"*.
  - **Detalle de Viajes Realizados:** Registros exhaustivos con línea, número de unidad, placa oficial, paradero de origen y destino, timestamp exacto, duración, monto debitado en puntos y soles, y estado (*Completado*).
  - **Detalle de Recargas Acreditadas:** Identificador de operación, canal de recarga (Yape/Plin/Agente), timestamp y puntos agregados.
* **Baja Definitiva de Cuenta (CU-11):**  
  - Botón protegido con confirmación modal.
  - Informa el saldo remanente y notifica el período de gracia de 15 días.

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

