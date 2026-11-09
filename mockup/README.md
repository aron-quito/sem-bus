# Plano Arquitectónico de Diseño UI/UX — Sistema BC (Bus Conectado)
## Mockup Interactivo / Prototipo Ejecutable (Figma Player)

> **Ubicación del Prototipo:** [`mockup/index.html`](file:///Users/aron/githubRepo/sem-bus/mockup/index.html)  
> **Documento Dedicado a la App Pasajero:** [`mockup/APP_PASAJERO.md`](file:///Users/aron/githubRepo/sem-bus/mockup/APP_PASAJERO.md)  
> **Finalidad:** Especificación visual, ergonómica y funcional de flujos para la **Línea 10 de Tacna** y validación de reglas de negocio. **NO es código web para la app final**, sino el blueprint arquitectónico para desarrollo 100% nativo (SwiftUI en iOS y Jetpack Compose en Android).

---

## 1. Cómo Ejecutar e Interactuar con el Mockup

Puedes abrir el prototipo de **3 formas inmediatas**:

### Opción A (La más rápida — Doble clic):
Abre directamente el archivo [`mockup/index.html`](file:///Users/aron/githubRepo/sem-bus/mockup/index.html) con **Safari** o **Google Chrome** en tu Mac.

### Opción B (Servidor local):
Desde tu terminal en la raíz del proyecto:
```bash
npx serve mockup
# O con Python:
python3 -m http.server 8080 --directory mockup
```
Luego abre `http://localhost:8080` en tu navegador.

---

## 2. Novedades de Experiencia y Arquitectura Implementadas

El prototipo incorpora las especificaciones clave de navegación e interacción solicitadas:

1. **Suscripción Automática y Ficha Informativa del Bus:**  
   * Al seleccionar un bus en el mapa, **se eliminaron los botones de pagar y suscribirse manualmente**.
   * La ficha del bus muestra foto general, chofer, brevete, calificación en estrellas, aforo semafórico en vivo y próxima parada con ETA.
   * La vinculación al viaje es **100% automática**: ocurre al escanear el QR en puerta o cuando el GPS del móvil detecta que el usuario está dentro del vehículo siguiendo la misma ruta.
   * Se incluye un botón de **`[📡 Detectar Bus]`** en la cabecera del mapa para forzar la sincronización si la app no lo detectó previamente.

2. **Paraderos Oficiales en el Mapa (3 Paraderos Clave):**  
   * En el mapa figuran exactamente los 3 paraderos estratégicos de la Línea 10: **Plaza Zela**, **P. Mercado** y **P. UNJBG**.
   * Al pulsar un paradero, se despliegan los buses próximos (ej. BUS 01 en ~3 min, BUS 07 en ~11 min) y el botón para programar la alerta con **2 temporizadores**:
     * **Temporizador 1 (Anticipación configurable):** Alerta previa a los $n = 5$, $10$ o $15$ minutos antes de que el bus alcance el paradero.
     * **Temporizador 2 (Inminente / Llegada):** Segunda alerta háptica y acústica cuando el bus está a escasos metros o segundos de arribar.

3. **Buscador de Destinos al estilo Google Maps con Botón Circular "Ir":**  
   * Al hacer clic en la barra de búsqueda, se despliega una lista sólida `#0F172A` de lugares e hitos de Tacna (*Mercadillo Bolognesi*, *Estadio Jorge Basadre*, *Plaza Zela*, *P. Mercado*, *P. UNJBG*).
   * Al lado de cada sugerencia se ubica un **botón circular azul con la flecha de "Ir"**:
     * **Si se pulsa el elemento:** La cámara del mapa se traslada al lugar y coloca un pin de ubicación. Si es un paradero, abre su ficha con ETAs y alertas.
     * **Si se pulsa el botón circular "Ir":** Activa directamente el **Escenario Pantalla Completa Google Maps** para calcular la ruta.

4. **Escenario Pantalla Completa Estilo Google Maps con Hoja de 3 Niveles:**  
   * Al pulsar el botón de cómo llegar (FAB cian `[↱]` o el botón circular `[Ir]`), la pantalla cambia completamente al modo navegación de **pantalla completa** (100% del iPhone 16):
     * **Cabecera Nativa:** Origen (*Tu ubicación*), Destino (*Mercadillo Bolognesi*), selector de modo (Auto, Moto, Bus, A pie) e inversión rápida `[⇅]`.
     * **Hoja Inferior Interactiva de 3 Alturas (Bottom Sheet Snaps):**
       - **Nivel 1: Compacto (Peek, ~140px):** Muestra la mejor opción (`12 min • 6 km`), botones `[Iniciar]`, `[Agregar paradas]` y `[Seguir ETA]`.
       - **Nivel 2: Detalle (Medium, ~340px):** Muestra el desglose de la mejor opción, hora de llegada (`Llegada: 12:10 a.m.`) y ahorro ecológico de combustible/tiempo.
       - **Nivel 3: Completo (Full, 90% altura):** Despliega el catálogo con **todas las formas posibles de llegar al destino** (BUS 01 12 min, BUS 07 18 min, Caminata 22 min), tarjeta fotográfica de destino y el acordeón con el **itinerario paso a paso**.

6. **Contención Estricta en el Marco Móvil (Cero Solapamientos en Pantalla):**  
   * Todos los popups, hojas flotantes (*bottom sheets*), diálogos modales (alertas de paradero, baja de cuenta) y notificaciones toast están **confinados estrictamente dentro del contenedor del smartphone** (`position: absolute; overflow: hidden`), evitando desbordes o solapamientos sobre el fondo de escritorio.

---

## 3. Dispositivos y Vistas Modeladas

| Vista | Dispositivo | Plataforma Nativa Destino | Características Principales |
| :--- | :---: | :---: | :--- |
| **App Pasajero** | iPhone 16 Pro | **iOS (SwiftUI puro)** | Marco con Dynamic Island, 4 pestañas (*Explorar*, *Pagar QR*, *Monedero*, *Perfil*), hoja flotante de viaje, buscador predictivo y trazador de rutas. |
| **Tablet Conductor** | Android 10" Horizontal | **Android (Jetpack Compose)** | Interfaz oscura anti-reflejo para cabina, tarjeta de cobro gigante de 3 segundos, botón táctil `[+1 CONADIS]` (S/. 0.00), averías y liquidación de turno. |
| **Módulo POS** | Validador Puerta | **Embedded Linux / Android POS** | Pantalla vertical con refresco de QR dinámico (30s) y sintetizador de sonido Web Audio API (`BEEP` verde 880Hz / `BEEP-BEEP` rojo 280Hz). |
| **Backoffice Web** | Monitor Escritorio | **Next.js / React Web** | Panel de supervisión de flota en tiempo real, gestión de tarifas (`fare_config`) y prórroga SUNEDU (`app_config`). |

---

## 4. Matriz de Pruebas Rápidas del Prototipo

| # | Flujo a Probar | Acción en el Mockup | Resultado Esperado |
| :--- | :--- | :--- | :--- |
| **1** | **Ficha de Bus sin Botones** | Toca el icono de `BUS 01` en el mapa | Se abre la ficha con foto, chofer, aforo y próxima parada, **sin botones manuales de pago o suscripción**. |
| **2** | **Detector Automático de Bus** | Pulsa el botón `[📡 Detectar Bus]` arriba a la derecha | La app escanea la telemetría, detecta la unidad y sincroniza el viaje abriendo la hoja en ruta. |
| **3** | **Paradero y Alertas (2 Timers)** | Toca el pin de *Paseo Cívico* y luego *"Alerta de Llegada"* | Abre el diálogo interno para elegir anticipación (5/10/15 min) y aviso inminente con sonido melódico. |
| **4** | **Buscador: Ver Lugar vs Botón "Ir"** | Escribe en el buscador: pulsa sobre *"Mercado Central"* o sobre su botón circular `[Ir]` | Si tocas el texto, centra el mapa y suelta el pin; si tocas el círculo `[Ir]`, abre de inmediato el trazador de ruta. |
| **5** | **FAB Circular de Direcciones** | Pulsa el botón flotante azul con flecha en la esquina inferior derecha | Se abre la vista de navegación estilo Google Maps con origen, destino, alternativas de ruta y pasos. |
| **6** | **Pago QR y Descenso** | Paga en la pestaña *"Pagar QR"* y luego en viaje pulsa *"Simular Descenso"* | Vincula el viaje automáticamente al pagar, actualiza la Dynamic Island y al descender cierra la sesión de viaje. |
