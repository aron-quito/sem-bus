# Proyecto BC (Bus Conectado) - Sistema Automatizado de Transporte Urbano
**Ámbito:** Tacna, Perú  
**Estado:** Fase 1: Especificación de Requerimientos y Casos de Uso Formales (UML 2.5 - QA Ready)

---

## 🚌 Visión del Proyecto
El proyecto **BC** moderniza el transporte urbano en Tacna mediante un ecosistema digital que automatiza el cobro de pasajes, el monitoreo de flotas en tiempo real, el cálculo de aforo y el acceso a tarifas preferenciales (General, Universitaria y CONADIS).

---

## 📚 Índice de Documentación del Sistema

### 1. Requerimientos del Sistema
* [01_Especificacion_Requerimientos_SRS.md](file:///Users/aron/githubRepo/sem-bus/docs/requerimientos/01_Especificacion_Requerimientos_SRS.md): Documento maestro de requerimientos funcionales, arquitectura de subsistemas y separación formal MVP (Fase 1) vs Hardware APC (Fase 2).
* [02_Matriz_Trazabilidad_Requerimientos.md](file:///Users/aron/githubRepo/sem-bus/docs/requerimientos/02_Matriz_Trazabilidad_Requerimientos.md): Matriz de reglas de negocio, estados de error y mecanismos de mitigación en puerta.

### 2. Casos de Uso (UML 2.5 - ProcessOn Style con Criterios BDD)
* [Índice y Diagrama General de Casos de Uso](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/README.md)
* [CU-00: Autenticación OTP por Celular y Creación de Monedero](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU00/CU00_Autenticacion_OTP_Onboarding.md) (`.md`, `.puml`, `.png`)
* [CU-01: Abordaje y Pago con App en POS](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU01/CU01_Abordaje_Pago_App.md) (`.md`, `.puml`, `.png`)
* [CU-02: Pago Directo con Yape/Plin (Sin App)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU02/CU02_Pago_Yape_Directo_Sin_App.md) (`.md`, `.puml`, `.png`)
* [CU-03: Acreditación de Carnet Universitario (SUNEDU)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU03/CU03_Acreditacion_Carnet_SUNEDU.md) (`.md`, `.puml`, `.png`)
* [CU-04: Operación de Turno en Tablet del Conductor](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU04/CU04_Operacion_Turno_Conductor_Tablet.md) (`.md`, `.puml`, `.png`)
* [CU-05: Recarga de Puntos BC mediante Pasarela](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU05/CU05_Recarga_Puntos_BC.md) (`.md`, `.puml`, `.png`)
* [CU-06: Descenso y Desacoplamiento por Geofencing](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU06/CU06_Descenso_Desacoplamiento_Geofencing.md) (`.md`, `.puml`, `.png`)
* [CU-07: Exploración de Rutas y Seguimiento en Vivo (Modo Invitado)](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU07/CU07_Monitoreo_Rutas_Modo_Invitado.md) (`.md`, `.puml`, `.png`)
