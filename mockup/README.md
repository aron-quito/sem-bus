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

2. **Paraderos en el Mapa con Alertas de 2 Temporizadores:**  
   * En el mapa figuran claramente los paraderos de la Línea 10 (*Cono Norte*, *Plaza Zela*, *Paseo Cívico*, *Mercado Central*, *UNJBG*).
   * Al pulsar un paradero, se despliegan los buses próximos (ej. BUS 01 en ~3 min, BUS 04 en ~10 min) y el botón para programar la alerta con **2 temporizadores**:
     * **Temporizador 1 (Anticipación configurable):** Alerta previa a los $n = 5$, $10$ o $15$ minutos antes de que el bus alcance el paradero.
     * **Temporizador 2 (Inminente / Llegada):** Segunda alerta háptica y acústica cuando el bus está a escasos metros o segundos de arribar.

3. **Buscador de Destinos al estilo Google Maps con Botón Circular "Ir":**  
   * Al escribir o hacer clic en la barra de búsqueda, se despliega una lista de lugares e hitos de Tacna (*Mercado Central*, *Paseo Cívico*, *UNJBG*, *Plaza Zela*, *Terminal Terrestre*).
   * Al lado de cada sugerencia se ubica un **botón circular azul con la flecha de "Ir"**:
     * **Si se pulsa el elemento:** La cámara del mapa se traslada al lugar y coloca un pin de ubicación. Si es un paradero, abre su ficha con ETAs y alertas; si es un hito general, muestra su tarjeta informativa con botón para cómo llegar.
     * **Si se pulsa el botón circular "Ir":** Activa directamente el **Modo de Trazado de Ruta Automático** calculando el paradero de origen, el bus a tomar y el paradero de desembarque.

4. **Botón Flotante Circular de Direcciones (FAB Inferior Derecho):**  
   * En la esquina inferior derecha del mapa flota el botón circular azul con flecha de navegación (idéntico a Google Maps).
   * Al pulsarlo, se abre la vista completa de navegación con dos campos en la cabecera:
     * **Origen:** Pre-llenado automáticamente con *"📍 Tu ubicación actual"*.
     * **Destino:** Campo para elegir el punto de llegada.
     * **Botón de Invertir (⇅):** Permite conmutar origen y destino instantáneamente.

5. **Múltiples Opciones de Ruta y Comparativa de Itinerarios:**  
   * Al calcular una ruta, se presentan tarjetas con alternativas:
     * **Opción 1 (Más rápida):** Línea 10 (BUS 01) • ~12 min • Próximo bus en ~3 min • Tarifa S/. 0.70 / S/. 1.40.
     * **Opción 2 (Siguiente / Menos concurrida):** Línea 10 (BUS 04) • ~18 min • Asientos libres garantizados.
     * **Opción 3 (Caminata directa):** A pie directo • ~22 min (1.5 km).
   * Incluye desglose visual paso a paso (caminar al paradero ➔ subir al bus ➔ viajar $X$ paradas ➔ bajar y caminar al destino final).

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
