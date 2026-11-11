# Documento de Aseguramiento de Calidad — Plan Maestro de Pruebas
## Sistema BC (Bus Conectado) — Transporte Urbano Automatizado (Tacna, Perú)

> **Documento:** `docs/testing/01_Test_Plan.md`  
> **Versión:** 1.0 (Noviembre 2026)  
> **Estándar:** SWEBOK v4 / IEEE 829 (Test Plan Specification)

---

## 1. Introducción y Alcance

Este Plan Maestro de Pruebas define la estrategia, herramientas, cobertura mínima y criterios de aceptación formal (**Definition of Done**) para validar la calidad, robustez financiera y seguridad del sistema **Bus Conectado (BC)** antes de su lanzamiento a producción en Tacna.

### 1.1. Módulos en Alcance (MVP Sprints 1 a 4)
* **App Pasajero:** Autenticación OTP (CU-00), Modo Invitado (CU-07), Pago QR en puerta (CU-01), Monedero y Recargas (CU-05), Acreditación SUNEDU (CU-03) y Desacoplamiento por Geofencing (CU-06).
* **App Conductor:** Apertura y cierre de turno (CU-04), semáforo de aforo y reporte de avería con reembolso.
* **Backend Central & Base de Datos:** Integridad transaccional ACID del monedero, validación de firmas Webhook y escalabilidad de WebSockets.

---

## 2. Niveles y Pirámide de Pruebas

```
                   /\
                  /  \     E2E Móvil (Maestro) — 10%
                 /────\
                /      \    Integración API & DB — 30%
               /────────\
              /          \   Pruebas Unitarias & Lógica — 60%
             /────────────\
```

| Nivel de Prueba | Herramienta | Cobertura Mínima | Responsable |
| :--- | :--- | :--- | :--- |
| **Pruebas Unitarias (Backend)** | `pytest` + `pytest-asyncio` | ≥ 80% en lógica de cobro y monedero | Backend Dev |
| **Pruebas de Base de Datos** | `pgTAP` / pruebas de triggers SQL | 100% en `fn_debit_wallet` y `fn_credit_wallet` | Database Admin |
| **Pruebas de Integración API** | `pytest` + `Testcontainers` (Postgres real) | 100% de endpoints documentados en OpenAPI | Backend / QA |
| **Pruebas E2E Móviles** | `Maestro CLI` (YAML scenarios en iOS/Android) | Flujos críticos (Login ➔ Recarga ➔ Pago QR) | QA Engineer |
| **Pruebas de Carga y Concurrencia** | `Locust` (Python) | 200 conexiones WS simultáneas + 50 cobros/seg | DevOps / QA |
| **Pruebas de Seguridad** | `OWASP ZAP` + `Bandit` / `pip-audit` | Cero vulnerabilidades críticas o altas | SecOps |
| **Pruebas de Campo (Field Testing)** | TestFlight (iOS) / Firebase Distribution (Android) | Prueba en ruta real Línea 10 Tacna (Plaza Zela ➔ Mercadillo) | Todo el equipo |

---

## 3. Criterios de Aceptación y Calidad (Definition of Ready / Done)

### 3.1. Definition of Ready (DoR) para Iniciar Desarrollo
1. Caso de Uso correspondiente especificado en BDD / Gherkin.
2. Contrato OpenAPI 3.0 definido y aprobado.
3. Componentes visuales y estados de error validados en el Mockup (`mockup/index.html`).

### 3.2. Definition of Done (DoD) para Mergear a `develop`
1. Cobertura de pruebas unitarias superior al 75%.
2. Cero alertas de linter (`flake8`, `black`, `swiftlint`, `ktlint`).
3. Pruebas de integración de base de datos pasando con éxito en GitHub Actions.
4. Código revisado y aprobado por al menos 1 revisor par.
5. Verificación de no-regresión en el escenario de saldo no-negativo (RN-04).

---

## 4. Clasificación y SLA de Defectos (Bugs)

| Severidad | Descripción y Criterio | SLA de Resolución |
| :--- | :--- | :--- |
| **P1 — Bloqueante** | Pérdida de dinero, cobro erróneo de puntos, caída general del backend o bloqueo de acceso a buses. | < 4 horas |
| **P2 — Crítico** | El QR no escanea, la telemetría del bus se congela por >30s o la tablet del chofer pierde enlace. | < 24 horas |
| **P3 — Mayor** | Fallo en filtros de historial, retardo en toast de notificación o fallo visual en un componente. | Siguiente Sprint |
| **P4 — Menor** | Detalle tipográfico, espaciado visual leve o traducción mejorable. | Backlog regular |

