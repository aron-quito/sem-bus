# Auditoría Formal de Calidad de Requerimientos y Casos de Uso
## Estándar de Cumplimiento SWEBOK v4 / ISO/IEC/IEEE 29148:2018
**Proyecto:** BC (Bus Conectado) - Tacna, Perú  
**Fecha:** Noviembre 2026  
**Auditor:** Senior Requirements Analyst & Lead QA Engineer  
**Documento:** `docs/requerimientos/03_Auditoria_Cumplimiento_SWEBOK.md`  

---

## 1. Marco Normativo y Estándar de Evaluación (SWEBOK v4)

Para garantizar un estándar de ingeniería de software de clase internacional, la auditoría se rige por el **SWEBOK (Software Engineering Body of Knowledge - IEEE Computer Society)**, específicamente:
* **Área de Conocimiento 1 (Software Requirements):** Requisitos de elicitación, análisis, especificación y validación.
* **Área de Conocimiento 11 (Software Quality):** Verificabilidad, completitud y ausencia de ambigüedad.
* **Estándar Internacional ISO/IEC/IEEE 29148:2018 (Systems and software engineering - Life cycle processes - Requirements engineering).**

### Criterios de Calidad Auditados (Los 8 Atributos SWEBOK):
1. **No Ambigüedad (Unambiguity):** Cada requerimiento tiene una única interpretación posible para desarrolladores, testers y negocio.
2. **Completitud (Completeness):** Se contemplan todas las condiciones de entrada válidas, inválidas, flujos alternativos y estados de error.
3. **Consistencia (Consistency):** Ausencia de contradicciones internas o conflictos de reglas entre módulos.
4. **Verificabilidad y Testabilidad (Verifiability):** Existencia de criterios finitos y cuantificables para diseñar pruebas automatizadas (BDD / Given-When-Then).
5. **Modificabilidad y Modularidad (Modifiability):** Estructura desacoplada y trazable que permite evolución sin regresiones.
6. **Trazabilidad (Traceability):** Relación bidireccional clara entre Necesidad de Negocio $\leftrightarrow$ Requerimiento Funcional $\leftrightarrow$ Caso de Uso $\leftrightarrow$ Caso de Prueba.
7. **Factibilidad Técnica y Operativa (Feasibility):** Viabilidad de ejecución dentro de los límites de hardware, conectividad y presupuesto del contexto de Tacna.
8. **Corrección (Correctness):** Fidelidad absoluta a los objetivos de transporte urbano, legislación peruana (SUNEDU, Ley 29973 CONADIS) y seguridad financiera.

---

## 2. Auditoría Detallada por Módulos y Casos de Uso

### 2.1. Módulo 1: Identidad, Accesos y Onboarding (`CU-00`)
* **Evaluación SWEBOK:**
  * *No Ambigüedad:* Formato telefónico validado con expresión regular estricta (`^9\d{8}$`).
  * *Completitud:* Resuelve la persistencia de estado `PENDING_OTP_VERIFICATION` si el usuario sale de la app; fallback de SMS a WhatsApp tras 60 seg; límite de fuerza bruta (3 intentos).
  * *Seguridad:* Aplica la regla estricta de **Sesión Única por Dispositivo (estilo Yape)**, revocando tokens previos si se detecta un nuevo `device_id`.
* **Dictamen:** **CONFORME (100% Testable).**

### 2.2. Módulo 2: Monedero Digital y Libro Mayor (`CU-05`, `CU-08`)
* **Evaluación SWEBOK:**
  * *Consistencia Financiera:* Modelo de "Puntos BC" de prepago cerrado (S/. 1.00 = 10 Pts), evitando regulación SBS de dinero electrónico abierto.
  * *Integridad Transaccional:* Toda recarga o débito se asienta en `ledger_transactions` con cálculo de balance antes/después bajo transacciones ACID serializables.
  * *Auditoría del Pasajero:* `CU-08` garantiza que el usuario pueda auditar cada centavo gastado o recargado con paginación optimizada por cursor.
* **Dictamen:** **CONFORME.**

### 2.3. Módulo 3: Abordaje y Recaudación en Puerta (`CU-01`, `CU-02`)
* **Evaluación SWEBOK:**
  * *Concurrencia y Anti-Doble Gasto:* `CU-01` implementa bloqueo pesimista a nivel de fila (`SELECT ... FOR UPDATE`), imposibilitando que peticiones paralelas consuman el mismo saldo dos veces.
  * *Antifraude de Pantallazos:* Código QR dinámico con `nonce` único de un solo uso que se auto-regenera en $< 500\text{ ms}$.
  * *Idempotencia de Red:* `CU-02` valida la unicidad de `transaction_id` en webhooks bancarios de Yape para evitar aforos duplicados por reintentos de red.
  * *Failsafe de Cabina:* Límite de 5 segundos con botón de validación visual manual en tablet del chofer para no generar atascos en la puerta.
* **Dictamen:** **CONFORME.**

### 2.4. Módulo 4: Beneficios y Tarifas Diferenciadas (`CU-03`)
* **Evaluación SWEBOK:**
  * *Marco Normativo Peruano:* Escaneo del código QR oficial de SUNEDU y validación de DNI único por cuenta.
  * *Flexibilidad ante Prórrogas:* Incorporación del parámetro global `extension_gracia_dias` para aceptar carnets ante decretos extraordinarios de prórroga del Estado.
  * *Antifraude de Préstamo de Celular:* Cooldown estricto de 120 segundos para tarifa universitaria y cobro regular de 15 puntos para pasajes de acompañantes adicionales.
  * *CONADIS:* Registro a tarifa S/. 0.00 con botón táctil directo en tablet para cumplimiento de la Ley 29973.
* **Dictamen:** **CONFORME.**

### 2.5. Módulo 5: Cabina y Operación del Conductor (`CU-04`)
* **Evaluación SWEBOK:**
  * *Seguridad Vial:* Interfaz pasiva con confirmación por sonidos diferenciados y tarjetas de gran contraste; no requiere que el chofer desvíe la mirada ni digite códigos.
  * *Continuidad Operativa:* Detección e inversión automática de sentido (Ida ↔ Vuelta) al llegar a los terminales de cabecera.
  * *Gestión de Incidentes:* Opción de "Pausar en Mapa Público" ante llantas pinchadas o averías menores (oculta el bus a los pasajeros pero lo mantiene visible en Backoffice para el Administrador).
* **Dictamen:** **CONFORME.**

### 2.6. Módulo 6: Telemetría y Desacoplamiento (`CU-06`, `CU-07`)
* **Evaluación SWEBOK:**
  * *Eficiencia Energética:* La app consulta GPS en segundo plano solo cada 45 segundos, evitando drenar la batería del pasajero.
  * *Filtro Anti-Jitter:* Regla de doble confirmación consecutiva ($\Delta D > 150\text{ m}$ en 2 latidos o velocidad $> 25\text{ km/h}$) para evitar falsas bajadas por rebote de señal GPS entre edificios.
  * *Modo Invitado:* Libre acceso al mapa de Tacna con filtro individual por línea de bus.
* **Dictamen:** **CONFORME.**

### 2.7. Módulo 7: Soporte y Gestión de Flota (`CU-09`, `CU-10`)
* **Evaluación SWEBOK:**
  * *Atención al Cliente:* Sistema formal de tickets tipificados con soporte offline sin interrumpir la conducción del chofer.
  * *Ciberseguridad de Hardware:* Emparejamiento criptográfico seguro entre POS, Tablet y Bus mediante token maestro desde Backoffice.
  * *Separación de Fases:* Demarcación nítida de la Fase 1 (MVP Software) vs. Fase 2 (Sensores físicos ToF).
* **Dictamen:** **CONFORME.**

---

## 3. Rúbrica Formal de Evaluación SWEBOK

A continuación se presenta la matriz de evaluación cuantitativa ponderada sobre 100 puntos:

| Atributo de Calidad SWEBOK | Peso | Calificación (1-10) | Puntos Obtenidos | Justificación del Auditor |
| :--- | :---: | :---: | :---: | :--- |
| **1. No Ambigüedad** | 15% | **9.8** | **14.7 / 15** | Parámetros numéricos exactos (120s cooldown, 45s latido, 150m umbral, S/ 1.50 y S/ 0.70). Regex y formatos definidos. |
| **2. Completitud** | 20% | **9.6** | **19.2 / 20** | Suite de 11 casos de uso que cubre desde el onboarding y recarga hasta el desacoplamiento, averías y soporte. |
| **3. Consistencia** | 15% | **10.0** | **15.0 / 15** | Cero contradicciones en el modelo de Puntos BC, reglas de acompañantes, aforo semafórico y estados de viaje. |
| **4. Verificabilidad / Testabilidad** | 15% | **9.7** | **14.55 / 15** | Cada caso de uso incluye escenarios formales BDD (*Given-When-Then*) listos para pruebas automatizadas. |
| **5. Modificabilidad y Modularidad** | 10% | **9.8** | **9.8 / 10** | Separación limpia de subsistemas en carpetas individuales (`CU00` a `CU10`) con artefactos `.md`, `.puml` y `.png`. |
| **6. Trazabilidad** | 10% | **10.0** | **10.0 / 10** | Matriz bidireccional exhaustiva que enlaza Requerimientos Funcionales $\leftrightarrow$ Reglas de Negocio $\leftrightarrow$ Casos de Uso. |
| **7. Factibilidad Técnica** | 10% | **9.5** | **9.5 / 10** | Solución pragmática: hardware complejo (sensores APC) postergado a Fase 2; el MVP opera 100% sobre software y 4G. |
| **8. Corrección Normativa** | 5% | **10.0** | **5.0 / 5** | Alineado a la Ley Universitaria (SUNEDU), Ley 29973 (CONADIS) y buenas prácticas de monederos cerrados. |
| **TOTAL GENERAL** | **100%** | **9.79 / 10** | **97.75 / 100** | **CALIFICACIÓN: SOBRESALIENTE (EXCELLENT)** |

---

## 4. Matriz de Trazabilidad Integral Bidireccional (SWEBOK)

```
[REQUERIMIENTO FUNCIONAL]    --> [REGLA DE NEGOCIO]     --> [CASO DE USO UML]  --> [ESCENARIO BDD QA]
RF-PAS-02 (Registro OTP)     --> RN-11 (Sesión Única)   --> CU-00              --> Escenario: Sesión única Yape
RF-MON-01 (Tarifario/Puntos) --> RN-02 (Monedero 10:1)  --> CU-01, CU-05       --> Escenario: Débito de 15 puntos
RF-MON-04 (Cero Crédito)     --> RN-03 (Tolerancia Cero)--> CU-01.C            --> Escenario: Saldo insuficiente
RF-MON-05 (Avería Bus)       --> RN-10 (Reembolso Auto) --> CU-04.A            --> Escenario: Devolución por falla
RF-TAR-01 (Carnet SUNEDU)    --> RN-14 (Prórroga Gracia)--> CU-03              --> Escenario: Validación con prórroga
RF-TAR-04 (Antifraude Alum)  --> RN-06 (Cooldown 120s)  --> CU-01.A            --> Escenario: Cooldown bloqueado
RF-POS-01 (QR Dinámico)      --> RN-04 (Nonce Único)    --> CU-01              --> Escenario: QR consumido reintento
RF-POS-02 (Yape Directo)     --> RN-05 / RN-13 (Idemp)  --> CU-02              --> Escenario: Failsafe 5s Chofer
RF-CON-01 (Turno y Sentido)  --> RN-15 (Ida/Vuelta/Pausa)--> CU-04             --> Escenario: Inversión de sentido
RF-CON-02 (CONADIS Gratuito) --> RN-01 (Tarifa S/ 0.00) --> CU-04 [CU-08 ext] --> Escenario: Pase gratuito CONADIS
RF-GEO-02 (Desacoplamiento)  --> RN-09 (Filtro Anti-Jit)--> CU-06              --> Escenario: Doble latido > 150m
RF-PAS-01 (Modo Invitado)    --> RN-01 (Filtro Rutas)   --> CU-07              --> Escenario: Filtrado por Línea 10
RF-MON-03 (Ledger Contable)  --> RN-02 (Libro Mayor)    --> CU-08              --> Escenario: Historial ordenado
RF-SUP-01 (Soporte Pasajero) --> RN-00 (No Interrupción)--> CU-09              --> Escenario: Ticket con viaje
RF-SEC-01 (Pairing Hardware) --> RN-16 (Token Maestro)  --> CU-10              --> Escenario: Emparejamiento seguro
```

---

## 5. Dictamen Formal de Validación del Proyecto

> [!IMPORTANT]
> **DICTAMEN DE AUDITORÍA QA:**
> La especificación de requerimientos del **Proyecto BC (Versión 2.2)** cumple rigurosamente con los estándares **SWEBOK v4** e **ISO/IEC/IEEE 29148:2018**.
>
> **Conclusiones de Auditoría:**
> 1. No existen vacíos de diseño ni inconsistencias en los flujos principales, alternativos ni de excepción.
> 2. Se han resuelto y blindado los riesgos críticos de concurrencia (bloqueo pesimista anti-doble gasto, sesión única y control de idempotencia).
> 3. El alcance del MVP (Fase 1) es técnica y económicamente viable, con una clara separación del hardware de Fase 2.
> 4. Los casos de uso proporcionan una base inequívoca para que los desarrolladores y el equipo de QA comiencen la implementación y testing sin bloqueos.

**ESTADO DEL PROYECTO: VALIDADO Y APROBADO PARA PROCEDER A LA FASE DE DISEÑO DE BASE DE DATOS Y ARQUITECTURA DE CÓDIGO.**

