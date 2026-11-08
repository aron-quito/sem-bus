# Proyecto BC (Bus Conectado) - Sistema Automatizado de Transporte Urbano
**Ámbito:** Tacna, Perú  
**Estado:** Fase 1 — Diseño de Base de Datos completado ✅ | SWEBOK Audit: 97.75/100 ✅

---

## 🚌 Visión del Proyecto
El proyecto **BC** moderniza el transporte urbano en Tacna mediante un ecosistema digital que automatiza el cobro de pasajes, el monitoreo de flotas en tiempo real, el cálculo de aforo y el acceso a tarifas preferenciales (General, Universitaria y CONADIS).

---

## 📚 Índice de Documentación del Sistema

### 1. Requerimientos del Sistema
* [01_Especificacion_Requerimientos_SRS.md](file:///Users/aron/githubRepo/sem-bus/docs/requerimientos/01_Especificacion_Requerimientos_SRS.md): Documento maestro de requerimientos funcionales, arquitectura de subsistemas y separación formal MVP (Fase 1) vs Hardware APC (Fase 2).
* [02_Matriz_Trazabilidad_Requerimientos.md](file:///Users/aron/githubRepo/sem-bus/docs/requerimientos/02_Matriz_Trazabilidad_Requerimientos.md): Matriz de reglas de negocio, estados de error y mecanismos de mitigación en puerta.

### 2. Casos de Uso (UML 2.5 - ProcessOn Style con Criterios BDD)
* [Índice y Diagrama General de Casos de Uso (UML 2.5 Consolidado)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/README.md)
* [CU-00: Autenticación OTP por Celular y Sesión Única (Yape)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU00/CU00_Autenticacion_OTP_Onboarding.md) (`.md`, `.puml`, `.png`)
* [CU-01: Abordaje y Pago con App en POS (Bloqueo Pesimista)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU01/CU01_Abordaje_Pago_App.md) (`.md`, `.puml`, `.png`)
* [CU-02: Pago Directo con Yape/Plin en POS (Idempotencia)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU02/CU02_Pago_Yape_Directo_Sin_App.md) (`.md`, `.puml`, `.png`)
* [CU-03: Acreditación de Carnet Universitario (Prórroga SUNEDU)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU03/CU03_Acreditacion_Carnet_SUNEDU.md) (`.md`, `.puml`, `.png`)
* [CU-04: Operación de Turno en Tablet (Ida/Vuelta y Pausa Mapa)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU04/CU04_Operacion_Turno_Conductor_Tablet.md) (`.md`, `.puml`, `.png`)
* [CU-05: Recarga de Puntos BC mediante Pasarela](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU05/CU05_Recarga_Puntos_BC.md) (`.md`, `.puml`, `.png`)
* [CU-06: Descenso y Desacoplamiento por Geofencing (Anti-Jitter)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU06/CU06_Descenso_Desacoplamiento_Geofencing.md) (`.md`, `.puml`, `.png`)
* [CU-07: Exploración de Rutas en Vivo con Filtro de Líneas](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU07/CU07_Monitoreo_Rutas_Modo_Invitado.md) (`.md`, `.puml`, `.png`)
* [CU-08: Consultar Historial de Gastos y Recargas](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU08/CU08_Historial_Gastos_Recargas.md) (`.md`, `.puml`, `.png`)
* [CU-09: Enviar Reportes, Sugerencias y Soporte Técnico](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU09/CU09_Reportes_Sugerencias_Soporte.md) (`.md`, `.puml`, `.png`)
* [CU-10: Vinculación Segura de Hardware (POS + Tablet + Bus)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU10/CU10_Vinculacion_Segura_Hardware_Admin.md) (`.md`, `.puml`, `.png`)
* [CU-11: Gestión de Perfil y Eliminación de Cuenta (Apple/Google)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU11/CU11_Gestion_Perfil_Eliminacion_Cuenta.md) (`.md`, `.puml`, `.png`)
* [CU-12: Panel de Administración Backoffice Web (Supervisión Flota)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU12/CU12_Panel_Administracion_Backoffice_Web.md) (`.md`, `.puml`, `.png`)

### 3. Auditoría SWEBOK v4
* [03_Auditoria_Cumplimiento_SWEBOK.md](file:///Users/aron/githubRepo/sem-bus/docs/requerimientos/03_Auditoria_Cumplimiento_SWEBOK.md): Auditoría formal bajo estándares SWEBOK v4 / ISO-IEC-IEEE 29148:2018 — **Score: 97.75/100 — VALIDADO Y APROBADO**

### 4. Modelo de Datos (PostgreSQL 15+)
* [01_Modelo_Entidad_Relacion.md](file:///Users/aron/githubRepo/sem-bus/docs/modelo_datos/01_Modelo_Entidad_Relacion.md): ERD completo — 17 entidades, 22 relaciones, 10 reglas de integridad, RLS, vistas y funciones atómicas
* [01_ERD_BC.puml](file:///Users/aron/githubRepo/sem-bus/docs/modelo_datos/01_ERD_BC.puml): Fuente Mermaid erDiagram del ERD
* [01_ERD_BC.png](file:///Users/aron/githubRepo/sem-bus/docs/modelo_datos/01_ERD_BC.png): Diagrama compilado (alta resolución, 689 KB)
* [02_Script_SQL_DDL.sql](file:///Users/aron/githubRepo/sem-bus/docs/modelo_datos/02_Script_SQL_DDL.sql): Script DDL completo PostgreSQL 15+ con ENUMs, índices, triggers, funciones atómicas (fn_debit_wallet, fn_credit_wallet, fn_revoke_previous_sessions) y vistas
