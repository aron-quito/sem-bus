# Proyecto BC - Catálogo y Diagramas UML de Casos de Uso (UML 2.5)
**Ubicación:** `docs/casos_de_uso/README.md`  
**Archivo Fuente PlantUML:** [diagrama_casos_de_uso.puml](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/diagrama_casos_de_uso.puml)  
**Versión:** 2.2 (Suite Completa y Auditada: CU-00 a CU-10)

---

## 1. Diagrama General de Casos de Uso (Renderizado en Alta Resolución)

<div align="center">
  <img src="diagrama_casos_de_uso.png" alt="Diagrama General de Casos de Uso - Ecosistema BC" style="max-width: 100%; height: auto; border: 1px solid #d1d5db; border-radius: 8px; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);" />
  <p><em>Figura: Mapa General de Casos de Uso del Ecosistema de Transporte Urbano BC (UML 2.5).</em></p>
</div>

---

## 2. Índice Maestro de Casos de Uso (Carpetas, PUML y PNG)

Cada caso de uso está especificado formalmente bajo la plantilla RUP/Cockburn con sus Criterios de Aceptación BDD (*Given-When-Then*), su código fuente PlantUML (`.puml`) y su imagen renderizada (`.png`):

| Código | Título del Caso de Uso | Módulo / Subsistema | Carpeta | Documento Markdown | Diagrama PNG |
| :---: | :--- | :--- | :---: | :---: | :---: |
| **CU-00** | **Autenticación OTP y Sesión Única (Yape)** | Onboarding / Identidad | [CU00/](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU00/) | [CU00_Autenticacion_OTP_Onboarding.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU00/CU00_Autenticacion_OTP_Onboarding.md) | [CU00.png](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU00/CU00_Autenticacion_OTP_Onboarding.png) |
| **CU-01** | **Abordar y Pagar Pasaje con App (Bloqueo Pesimista)** | Abordaje y Pasajes | [CU01/](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU01/) | [CU01_Abordaje_Pago_App.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU01/CU01_Abordaje_Pago_App.md) | [CU01.png](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU01/CU01_Abordaje_Pago_App.png) |
| **CU-02** | **Pagar Directo con Yape en POS (Idempotencia)** | Recaudación Directa | [CU02/](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU02/) | [CU02_Pago_Yape_Directo_Sin_App.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU02/CU02_Pago_Yape_Directo_Sin_App.md) | [CU02.png](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU02/CU02_Pago_Yape_Directo_Sin_App.png) |
| **CU-03** | **Acreditar Carnet Universitario (Prórroga SUNEDU)** | Beneficios y Tarifas | [CU03/](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU03/) | [CU03_Acreditacion_Carnet_SUNEDU.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU03/CU03_Acreditacion_Carnet_SUNEDU.md) | [CU03.png](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU03/CU03_Acreditacion_Carnet_SUNEDU.png) |
| **CU-04** | **Operar Turno en Tablet (Ida/Vuelta y Pausa Mapa)** | Cabina y Flota | [CU04/](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU04/) | [CU04_Operacion_Turno_Conductor_Tablet.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU04/CU04_Operacion_Turno_Conductor_Tablet.md) | [CU04.png](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU04/CU04_Operacion_Turno_Conductor_Tablet.png) |
| **CU-05** | **Recargar Puntos BC mediante Pasarela** | Monedero Digital | [CU05/](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU05/) | [CU05_Recarga_Puntos_BC.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU05/CU05_Recarga_Puntos_BC.md) | [CU05.png](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU05/CU05_Recarga_Puntos_BC.png) |
| **CU-06** | **Descenso y Desacoplamiento GPS (Anti-Jitter)** | Telemetría Autónoma | [CU06/](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU06/) | [CU06_Descenso_Desacoplamiento_Geofencing.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU06/CU06_Descenso_Desacoplamiento_Geofencing.md) | [CU06.png](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU06/CU06_Descenso_Desacoplamiento_Geofencing.png) |
| **CU-07** | **Consultar Rutas en Vivo con Filtro de Líneas** | Exploración y Mapa | [CU07/](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU07/) | [CU07_Monitoreo_Rutas_Modo_Invitado.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU07/CU07_Monitoreo_Rutas_Modo_Invitado.md) | [CU07.png](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU07/CU07_Monitoreo_Rutas_Modo_Invitado.png) |
| **CU-08** | **Consultar Historial de Gastos y Recargas** | Auditoría y Monedero | [CU08/](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU08/) | [CU08_Historial_Gastos_Recargas.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU08/CU08_Historial_Gastos_Recargas.md) | [CU08.png](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU08/CU08_Historial_Gastos_Recargas.png) |
| **CU-09** | **Enviar Reportes, Sugerencias y Soporte** | Atención al Pasajero | [CU09/](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU09/) | [CU09_Reportes_Sugerencias_Soporte.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU09/CU09_Reportes_Sugerencias_Soporte.md) | [CU09.png](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU09/CU09_Reportes_Sugerencias_Soporte.png) |
| **CU-10** | **Vinculación Segura de Hardware (POS + Tablet)** | Flota y Ciberseguridad | [CU10/](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU10/) | [CU10_Vinculacion_Segura_Hardware_Admin.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU10/CU10_Vinculacion_Segura_Hardware_Admin.md) | [CU10.png](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU10/CU10_Vinculacion_Segura_Hardware_Admin.png) |
