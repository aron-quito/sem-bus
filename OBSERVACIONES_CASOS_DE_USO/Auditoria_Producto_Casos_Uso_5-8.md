# Sesión de Auditoría de Producto: Casos de Uso CU-05 al CU-08

**Proyecto:** Ecosistema Digital de Transporte Urbano BC (Bus Conectado) - Tacna, Perú  
**Fase:** Auditoría y Refinamiento Funcional de Casos de Uso (CU-05, CU-06, CU-07, CU-08)  
**Fecha:** Noviembre 2026  
**Documento:** `OBSERVACIONES_CASOS_DE_USO/Auditoria_Producto_Casos_Uso_5-8.md`  
**Auditoría y Revisión:** Equipo de Arquitectura de Software, Negocio y UX  

---

## 1. Resumen Ejecutivo de la Sesión

Esta segunda sesión de auditoría analiza la viabilidad económica, la eficiencia telemática en campo, el posicionamiento estratégico frente a inversionistas y la ergonomía visual de los casos de uso **CU-05 a CU-08**.

### Ejes de Intervención:
1. **Barrera de Entrada Financiera en Recargas (CU-05):** Análisis de comisiones bancarias vs. fricción de usuario al exigir S/. 5.00 como monto mínimo. Se aprueba la reducción a **S/. 2.00** para mitigar el temor de "dinero retenido" en el monedero digital.
2. **Eficiencia Telemática y Ahorro de Recursos (CU-06):** Reemplazo del polling continuo (heartbeat cada 45s) por un modelo **dirigido por eventos en paraderos** (*Stop-Driven Checkpoints*). Durante el trayecto entre paraderos, el proceso permanece inactivo (*Dormant*).
3. **Estrategia de Negocio y Foso Competitivo (CU-07):** Blindaje del valor del producto frente a inversionistas. Se restringe la exploración de rutas a **nuestras líneas equipadas con el ecosistema BC**, evitando diluir la plataforma como un simple "agregador pasivo de rutas".
4. **Claridad Contable y Segregación de UX (CU-08):** Separación obligatoria de la interfaz en dos pestañas independientes: **Historial de Viajes (Gastos Operativos)** y **Historial de Recargas (Abonos Financieros)**.

---

## 2. Matriz de Hallazgos y Decisiones de Auditoría

| Caso de Uso | Aspecto Evaluado | Especificación Original | Decisión de Auditoría / Solución Técnica | Impacto en Producto |
| :--- | :--- | :--- | :--- | :--- |
| **CU-05** | Monto mínimo de recarga | Mínimo S/. 5.00 (50 Puntos BC). Percepción de pérdida de liquidez. | **Mínimo S/. 2.00 en Yape/Plin:** Cubre 1 pasaje adulto (S/. 1.50) con saldo remanente o casi 3 universitarios. Tarjetas mantienen S/. 5.00 por comisiones fijas. | Elimina la barrera de adopción inicial y el miedo a inmovilizar capital en puntos. |
| **CU-06** | Comprobación de descenso (Heartbeat) | Background task del smartphone enviando GPS cada 45s durante todo el viaje. | **Checkpoints Exclusivos en Paraderos:** La verificación solo se ejecuta cuando el bus arriba a la geocerca de un paradero. Entre paraderos entra en modo reposo (*Dormant*). | Ahorro masivo de batería, menor latencia y caída del 85% en peticiones innecesarias al backend. |
| **CU-07** | Alcance de rutas en el mapa | Exposición de "múltiples líneas de la ciudad", actuando como agregador general. | **Enfoque en Flota BC Propietaria:** El mapa destaca exclusivamente unidades conectadas al sistema BC. Líneas terceras solo entran bajo modelo SaaS/Partner de pago. | Protege el atractivo para inversionistas: somos una solución tecnológica integral, no un directorio gratuito. |
| **CU-08** | Visualización de movimientos | Lista cronológica unificada mezclando débitos de viaje y abonos de dinero. | **Segregación Estructural en Dos Pestañas:** Pestaña 1: "Mis Viajes" (auditoría operativa). Pestaña 2: "Mis Recargas" (auditoría financiera y comprobantes). | Lectura limpia e intuitiva; resolución inmediata de dudas de saldo sin fatiga cognitiva. |

---

## 3. Diagrama de Arquitectura Refinada (CU-05 a CU-08)

```mermaid
flowchart TD
    subgraph CU05["💳 CU-05: Recarga Accesible"]
        A1[Usuario selecciona recarga] --> A2{¿Método?}
        A2 -- Yape / Plin --> A3[Monto Mínimo: S/. 2.00 -> 20 Pts]
        A2 -- Tarjeta Débito --> A4[Monto Mínimo: S/. 5.00 -> 50 Pts]
        A3 --> A5[Acreditación Inmediata]
        A4 --> A5
    end

    subgraph CU06["🛑 CU-06: Checkpoint en Paradas"]
        B1[Bus en Tránsito] -->|Entre Paraderos| B2[Modo Dormant: Cero Polling GPS]
        B1 -->|Arriba a Paradero X| B3[Evento: Bus en Geocerca Paradero]
        B3 --> B4{¿Pasajero desciende?}
        B4 -- Sí --> B5[Desacoplamiento y Cierre de Viaje]
        B4 -- No --> B2
    end

    subgraph CU07["🎯 CU-07: Foso de Producto"]
        C1[Explorador de Rutas] --> C2[Línea(s) del Consorcio BC]
        C2 --> C3[Muestra: Telemetría Real + Aforo + Cobro Digital]
        C3 --> C4[No se regala visibilidad a flotas informales o sin hardware]
    end

    subgraph CU08["📑 CU-08: Segregación UX"]
        D1[Sección Movimientos] --> D2[Tab 1: Mis Viajes]
        D1 --> D3[Tab 2: Mis Recargas]
        D2 --> D4[Línea, Placa, Paraderos, Tarifa]
        D3 --> D5[Monto PEN, Puntos, Método, Recibo]
    end
```

---

## 4. Análisis Detallado por Caso de Uso

### 4.1. Caso de Uso CU-05: Monto Mínimo de Recarga y Realidad de Pasarelas

#### Diagnóstico del Problema:
* **Fricción Psicológica de Conversión:** Obligar a un usuario nuevo en Tacna a recargar S/. 5.00 para probar la app genera resistencia. Un pasaje adulto regular cuesta S/. 1.50 y el universitario S/. 0.70; inmovilizar S/. 5.00 en "Puntos BC" (que no pueden retirarse en efectivo ni gastarse en una bodega) se percibe como una "pérdida de liquidez".
* **¿Existe impedimento legal o regulatorio?**  
  **No.** La Superintendencia de Banca y Seguros (SBS) y el Banco Central de Reserva del Perú (BCRP) no imponen un monto mínimo para el prepago de servicios cerrados de transporte (*closed-loop payment systems*).
* **El Origen Técnico del Mínimo de S/. 5.00:** Las pasarelas de pago con tarjeta (Niubiz, Culqi, Stripe) aplican una comisión fija por transacción de aprox. `S/. 0.50 + 3.99% + IGV`.  
  * Si un usuario recargase S/. 2.00 con tarjeta, la comisión bancaria representaría más del **30% del monto**, destruyendo el margen del operador.
  * Sin embargo, con **Yape / Plin P2P o QR Empresas**, el esquema de tarifas no tiene esa penalización fija en microtransacciones.

#### Directiva de Auditoría:
1. **Diferenciación de Montos Mínimos por Canal:**
   * **Vía Yape / Plin:** Monto mínimo reducido a **S/. 2.00** (= 20 Puntos BC).  
     *(Permite pagar un pasaje completo de S/. 1.50 y conservar 5 puntos de saldo, o pagar casi 3 pasajes universitarios de 7 puntos).*
   * **Vía Tarjetas Bancarias (Visa / Mastercard):** Se mantiene el umbral mínimo de **S/. 5.00** para proteger los costos de transacción bancaria.
2. **Botones de Recarga Rápida en Interfaz:**
   * Botones predeterminados: `[ S/. 2.00 ]`, `[ S/. 5.00 ]`, `[ S/. 10.00 ]`, `[ S/. 20.00 ]`.
3. **Incentivo por Volumen:**
   * Recargas de S/. 10.00 o más reciben una bonificación (ej. S/. 10.00 = 105 Puntos BC), motivando voluntariamente recargas mayores sin castigar al usuario que solo quiere completar su viaje del día.

---

### 4.2. Caso de Uso CU-06: Desacoplamiento Basado en Checkpoints de Paraderos

#### Diagnóstico del Problema:
* La especificación original estipulaba que la app móvil en segundo plano despertase cada **45 segundos** con una tarea de fondo (`Background Task`), capturara coordenadas GPS y enviara un `POST /api/v1/trips/heartbeat`.
* **Inconsistencia Operativa:** Físicamente, un pasajero **no puede descender de un bus en marcha a 40 km/h** a mitad de una avenida. Las bajadas ocurren únicamente cuando el vehículo se detiene en un **paradero oficial** o en una intersección semafórica prolongada.
* Mantener 2,000 celulares enviando peticiones HTTP cada 45 segundos degrada la batería de terminales de gama media/baja y sobrecarga innecesariamente el backend.

#### Directiva de Auditoría:
1. **Arquitectura Dirigida por Eventos en Paraderos (*Stop-Driven Checkpoints*):**
   * El POS/Tablet del bus es el que posee el enlace GPS de alta precisión y conoce su ruta oficial.
   * **En Ruta (Inter-paraderos):** La tarea de comprobación de descenso en los teléfonos permanece en **Modo Reposo Absoluto (*Dormant*)**. Cero peticiones de red y cero lecturas de GPS en el celular del pasajero.
2. **Activación del Checkpoint de Descenso:**
   * Cuando el bus ingresa a la geocerca de 30 metros del **Paradero X** y reduce su velocidad a menos de 5 km/h, el backend marca el evento: `BUS_ARRIVED_AT_STOP`.
   * **Evaluación de Descenso:**
     * Conforme el bus abandona el paradero y retoma velocidad (> 15 km/h), el backend verifica el vector de distanciamiento.
     * Si el pasajero no continúa dentro del radio de influencia del bus, se ejecuta el cierre del viaje (`TRIP_COMPLETED`), vinculando automáticamente el viaje al `Paradero X` como punto de descenso oficial.
3. **Preservación de la Alarma de Destino:**
   * La alarma de proximidad (CU-06.A) no requiere GPS activo en el teléfono: se calcula en el servidor en base al GPS del bus. Cuando el bus se aproxima a 400m de la parada pre-marcada por el usuario, el servidor le envía un Push de alta prioridad que hace vibrar el smartphone.

---

### 4.3. Caso de Uso CU-07: Estrategia de Producto y Foso Tecnológico Frente a Inversionistas

#### Diagnóstico del Problema:
* Proyectar la app como una plataforma multiruta donde figuran todas las líneas de transporte de la ciudad (incluso las que no cuentan con validadores POS ni telemetría BC) diluye la propuesta de valor:
  1. **Confusión para Inversionistas y Operadores:** Un inversionista evaluará el proyecto como un "agregador pasivo de mapas" (como Moovit o TuRuta), un mercado saturado y de difícil monetización, en lugar de apreciarlo como un **ecosistema integral de movilidad (Hardware POS + Smart Ticketing + Control de Flota + Recaudación)**.
  2. **Riesgo Operativo:** Publicitar líneas informales o buses que no cumplen frecuencias genera quejas de usuarios que culpan a la App BC por retrasos de flotas que no pertenecen a nuestro sistema.

#### Directiva de Auditoría:
1. **Fase 1 (MVP y Lanzamiento Comercial): Enfoque Propietario Exclusivo:**
   * El catálogo y mapa en vivo despliega **únicamente la(s) línea(s) y unidades pertenecientes al Consorcio o Empresa de Transporte aliada**.
   * Solo se muestran buses que cuentan con el hardware BC instalado (garantizando aforo semafórico real, tiempo estimado certero y capacidad de pago digital en puerta).
2. **Fase 2 (Modelo de Expansión B2B / SaaS de Alojamiento):**
   * Si otra empresa de transporte en Tacna desea aparecer en la aplicación, no lo hará como "información abierta gratuita", sino adquiriendo el paquete tecnológico:
     * O bien instalan los módulos POS/Tablet BC para recaudación integrada.
     * O abonan un canon mensual de software telemático (SaaS de flota).
   * De este modo, la plataforma preserva su foso defensivo (*moat*), demostrando solidez financiera e incentivo de venta clara ante cualquier mesa de inversión.

---

### 4.4. Caso de Uso CU-08: Segregación Estructural en Historial (Viajes vs Recargas)

#### Diagnóstico del Problema:
* Mezclar en un solo feed cronológico infinito los débitos por viajes (`-15 Pts`, `-7 Pts`) con los créditos por recargas bancarias (`+50 Pts / S/. 5.00`) genera confusión en el pasajero:
  * Cuando un usuario desea auditar cuánto ha gastado en transporte en la semana, debe sortear comprobantes de Yape entre docenas de cobros de bus.
  * Cuando una recarga demora o se requiere verificar un recibo bancario, el registro queda sepultado por los abordajes diarios.

#### Directiva de Auditoría:
1. **Arquitectura de Interfaz en Dos Pestañas Nativas:**
   * **Pestaña A: "Mis Viajes" (Historial Operativo / Débitos):**
     * Despliega exclusivamente viajes realizados.
     * Cada tarjeta exhibe: Línea de bus, placa, fecha/hora exacta, tipo de tarifa aplicada (Adulto / Universitario / Acompañantes) y paraderos de origen y destino.
     * Indicador visual en color neutro o rojo tenue con el débito de puntos (`-15 Pts`).
   * **Pestaña B: "Mis Recargas" (Historial Financiero / Créditos):**
     * Despliega exclusivamente abonos de dinero.
     * Cada tarjeta exhibe: Importe pagado en Soles (`S/. 2.00`, `S/. 10.00`), puntos acreditados (`+20 Pts`, `+100 Pts`), pasarela utilizada (Yape, Plin o Tarjeta), código de operación y botón de **`[Ver Recibo Digital]`**.
2. **Optimización en Backend (`/api/v1/wallet`):**
   * Proporcionar parámetros de segmentación rápida en la API:
     * `GET /api/v1/wallet/trips?page=1`
     * `GET /api/v1/wallet/recharges?page=1`
   * Reducción de la carga de base de datos al no requerir joins complejos para desplegar la vista principal de viajes.

---

## 5. Resumen de Impacto Técnico y Próximos Pasos

```
+---------------------------------------------------------------------------------------------------+
| IMPACTO GLOBAL DE LA AUDITORÍA CU-05 AL CU-08:                                                    |
| 1. Reducción de fricción de adopción inicial: Mínimo accesible de S/. 2.00 en Yape.              |
| 2. Reducción de consumo de batería móvil: Polling inteligente solo en paraderos físicos.         |
| 3. Protección del modelo de negocio e inversión: Enfoque cerrado en flotas aliadas de valor.     |
| 4. Ergonomía UX superior: Historiales claramente segregados (Operativo vs Financiero).           |
+---------------------------------------------------------------------------------------------------+
```

### Acciones Inmediatas de Ingeniería:
1. **Actualizar Especificaciones UML:** Reflejar el modo *Dormant* en el diagrama de actividades de `CU-06` y la estructura dual en `CU-08`.
2. **Ajuste de Mockup UI (`mockup/index.html`):**
   * Configurar el modal de recargas con la opción de S/. 2.00 para pagos con Yape.
   * Diseñar las pestañas separadas de "Viajes" y "Recargas" en la pantalla de monedero.
3. **Verificación de Base de Datos:**
   * Garantizar que `ledger_transactions` y `trips` permitan indexación eficiente por tipo de movimiento (`TRIP_DEBIT` vs `RECHARGE_CREDIT`) para consultas segmentadas de alta velocidad.

---
*Documento de auditoría técnica emitido y resguardado en el repositorio de ingeniería bajo `OBSERVACIONES_CASOS_DE_USO/Auditoria_Producto_Casos_Uso_5-8.md`.*

