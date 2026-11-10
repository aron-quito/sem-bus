# Proyecto BC (Bus Conectado) - Sistema Automatizado de Transporte Urbano
**Ámbito:** Tacna, Perú  
**Estado:** Etapa Pre-Código Completada (Requerimientos ✅ | Modelo de Datos ✅ | Prototipo UI/UX ✅ | Arquitectura C4 & OpenAPI ✅ | Plan de Pruebas ✅) — SWEBOK v4 Audit: 97.75/100 ✅

---

## 🚌 Visión del Proyecto
El proyecto **BC** moderniza el transporte urbano en Tacna mediante un ecosistema digital que automatiza el cobro de pasajes, el monitoreo de flotas en tiempo real, el cálculo de aforo y el acceso a tarifas preferenciales (General, Universitaria y CONADIS).

---

## 📚 Índice Maestro de Documentación del Sistema

### 1. Requerimientos del Sistema
* [01_Especificacion_Requerimientos_SRS.md](file:///Users/aron/githubRepo/sem-bus/docs/requerimientos/01_Especificacion_Requerimientos_SRS.md): Documento maestro de requerimientos funcionales, arquitectura de subsistemas y separación formal MVP (Fase 1) vs Hardware APC (Fase 2).
* [02_Matriz_Trazabilidad_Requerimientos.md](file:///Users/aron/githubRepo/sem-bus/docs/requerimientos/02_Matriz_Trazabilidad_Requerimientos.md): Matriz de reglas de negocio, estados de error y mecanismos de mitigación en puerta.
* [03_Auditoria_Cumplimiento_SWEBOK.md](file:///Users/aron/githubRepo/sem-bus/docs/requerimientos/03_Auditoria_Cumplimiento_SWEBOK.md): Auditoría formal bajo estándares SWEBOK v4 / ISO-IEC-IEEE 29148:2018 — **Score: 97.75/100 — VALIDADO Y APROBADO**.

### 2. Casos de Uso (UML 2.5 - ProcessOn Style con Criterios BDD)
* [Índice y Diagrama General de Casos de Uso (UML 2.5 Consolidado)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/README.md)
* [CU-00: Autenticación OTP por Celular y Sesión Única (Yape)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU00/CU00_Autenticacion_OTP_Onboarding.md)
* [CU-01: Abordaje y Pago con App en POS (Bloqueo Pesimista)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU01/CU01_Abordaje_Pago_App.md)
* [CU-02: Pago Directo con Yape/Plin en POS (Idempotencia)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU02/CU02_Pago_Yape_Directo_Sin_App.md)
* [CU-03: Acreditación de Carnet Universitario (Prórroga SUNEDU)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU03/CU03_Acreditacion_Carnet_SUNEDU.md)
* [CU-04: Operación de Turno en Tablet (Ida/Vuelta y Pausa Mapa)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU04/CU04_Operacion_Turno_Conductor_Tablet.md)
* [CU-05: Recarga de Puntos BC mediante Pasarela](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU05/CU05_Recarga_Puntos_BC.md)
* [CU-06: Descenso y Desacoplamiento por Geofencing (Anti-Jitter)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU06/CU06_Descenso_Desacoplamiento_Geofencing.md)
* [CU-07: Monitoreo de Rutas en Modo Invitado](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU07/CU07_Monitoreo_Rutas_Modo_Invitado.md)
* [CU-08: Consultar Historial de Gastos y Recargas](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU08/CU08_Historial_Gastos_Recargas.md)
* [CU-09: Enviar Reportes, Sugerencias y Soporte Técnico](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU09/CU09_Reportes_Sugerencias_Soporte.md)
* [CU-10: Vinculación Segura de Hardware (POS + Tablet + Bus)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU10/CU10_Vinculacion_Segura_Hardware_Admin.md)
* [CU-11: Gestión de Perfil y Eliminación de Cuenta (Apple/Google)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU11/CU11_Gestion_Perfil_Eliminacion_Cuenta.md)
* [CU-12: Panel de Administración Backoffice Web (Supervisión Flota)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU12/CU12_Panel_Administracion_Backoffice_Web.md)

### 3. Modelo de Datos (PostgreSQL 15+)
* [01_Modelo_Entidad_Relacion.md](file:///Users/aron/githubRepo/sem-bus/docs/modelo_datos/01_Modelo_Entidad_Relacion.md): ERD completo — 17 entidades, 22 relaciones, 10 reglas de integridad, RLS, vistas y funciones atómicas.
* [02_Script_SQL_DDL.sql](file:///Users/aron/githubRepo/sem-bus/docs/modelo_datos/02_Script_SQL_DDL.sql): Script DDL completo PostgreSQL 15+ con triggers de libro mayor inmutable (`fn_debit_wallet`, `fn_credit_wallet`).

### 4. Arquitectura de Software y Contratos (C4 Model & OpenAPI)
* [01_C4_Contexto.md](file:///Users/aron/githubRepo/sem-bus/docs/arquitectura/01_C4_Contexto.md): C4 Level 1 — Contexto de sistema, actores humanos y sistemas externos (Yape/Plin, SUNEDU, Twilio).
* [02_C4_Contenedores.md](file:///Users/aron/githubRepo/sem-bus/docs/arquitectura/02_C4_Contenedores.md): C4 Level 2 — Contenedores (FastAPI, Redis 7, PostgreSQL 15, WebSockets Hub, Workers).
* [03_Stack_Tecnico.md](file:///Users/aron/githubRepo/sem-bus/docs/arquitectura/03_Stack_Tecnico.md): Architecture Decision Records (ADR) formales por capa y matriz de dependencias.
* [04_API_Contract.yaml](file:///Users/aron/githubRepo/sem-bus/docs/arquitectura/04_API_Contract.yaml): Contrato maestro **OpenAPI 3.0.3** con todos los endpoints REST y modelos del MVP.
* [05_Push_Strategy.md](file:///Users/aron/githubRepo/sem-bus/docs/arquitectura/05_Push_Strategy.md): Estrategia dual APNs (iOS Live Activities) + FCM (Android Heads-up).
* [06_Entornos.md](file:///Users/aron/githubRepo/sem-bus/docs/arquitectura/06_Entornos.md): Configuración de entornos (dev, staging, prod), manifiesto Docker Compose y gestión de secretos.

### 5. Aseguramiento de Calidad y Pruebas (QA)
* [01_Test_Plan.md](file:///Users/aron/githubRepo/sem-bus/docs/testing/01_Test_Plan.md): Plan Maestro de Pruebas (IEEE 829), pirámide de testing, herramientas y Definition of Done (DoD).
* [02_Casos_Prueba_MVP.md](file:///Users/aron/githubRepo/sem-bus/docs/testing/02_Casos_Prueba_MVP.md): Catálogo detallado de casos de prueba del MVP derivados de criterios BDD.

### 6. Prototipo Interactivo Ejecutable y Blueprints UI/UX
* [mockup/index.html](file:///Users/aron/githubRepo/sem-bus/mockup/index.html): **Prototipo Interactivo Ejecutable (+4,200 líneas)** con iPhone 16 Pro, Tablet Android de Conductor (Cabina), Validador POS en Puerta, Onboarding/OTP, Modo Invitado, modales de error y sintetizador de audio real (Web Audio API).
* [mockup/APP_PASAJERO.md](file:///Users/aron/githubRepo/sem-bus/mockup/APP_PASAJERO.md): Blueprint de Arquitectura UI/UX para la App de Pasajero (iOS / Android).
* [mockup/APP_CONDUCTOR.md](file:///Users/aron/githubRepo/sem-bus/mockup/APP_CONDUCTOR.md): Blueprint de Arquitectura UI/UX para la App de Tablet Conductor (Android 10").

### 7. Convenciones y Flujo de Trabajo
* [CONTRIBUTING.md](file:///Users/aron/githubRepo/sem-bus/CONTRIBUTING.md): Política de ramas Gitflow, Conventional Commits y pasos para levantar el entorno local.
