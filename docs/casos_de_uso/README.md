# Proyecto BC - Catálogo y Diagrama de Casos de Uso (MVP)
**Ubicación:** `docs/casos_de_uso/README.md`  
**Versión:** 1.0

---

## 1. Diagrama General de Casos de Uso

```mermaid
flowchart LR
    subgraph Actores
        P[Pasajero con App]
        P_Anon[Pasajero Invitado]
        P_Direct[Pasajero Sin App]
        C[Conductor / Chofer]
        B[Backend / Sistema BC]
    end

    subgraph Casos_de_Uso [Casos de Uso del Sistema BC]
        CU01["CU-01: Abordaje y Pago con App en POS"]
        CU02["CU-02: Pago Directo con Yape/Plin (Sin App)"]
        CU03["CU-03: Acreditación de Carnet SUNEDU"]
        CU04["CU-04: Operación de Turno y Control (Tablet Chofer)"]
        CU05["CU-05: Recarga de Puntos BC"]
        CU06["CU-06: Descenso y Desacoplamiento por Geocerca"]
        CU07["CU-07: Consulta Libre de Mapa y Rutas (Modo Invitado)"]
        CU08["CU-08: Registro de Pasajero CONADIS (S/. 0.00)"]
    end

    P --> CU01
    P --> CU03
    P --> CU05
    P --> CU06
    P_Anon --> CU07
    P_Direct --> CU02
    P_Direct --> CU08
    C --> CU04
    C --> CU08
    B --> CU01
    B --> CU02
    B --> CU06
```

---

## 2. Índice de Especificación Detallada de Casos de Uso

| Código | Nombre del Caso de Uso | Actores Principales | Documento de Detalle |
| :--- | :--- | :--- | :--- |
| **CU-01** | Abordaje y Pago con App en POS | Pasajero, POS en Bus, Tablet Chofer | [CU01_Abordaje_Pago_App.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU01_Abordaje_Pago_App.md) |
| **CU-02** | Pago Directo con Yape/Plin (Sin App) | Pasajero sin App, POS en Bus, Pasarela Bancaria | [CU02_Pago_Yape_Directo_Sin_App.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU02_Pago_Yape_Directo_Sin_App.md) |
| **CU-03** | Acreditación de Carnet Universitario | Pasajero Estudiante, SUNEDU, Backend | [CU03_Acreditacion_Carnet_SUNEDU.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU03_Acreditacion_Carnet_SUNEDU.md) |
| **CU-04** | Operación de Turno en Tablet | Conductor, Backend | [CU04_Operacion_Turno_Conductor_Tablet.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU04_Operacion_Turno_Conductor_Tablet.md) |
| **CU-05** | Recarga de Puntos BC | Pasajero, Pasarela de Pagos (Yape/Plin/Tarjeta) | [CU05_Recarga_Puntos_BC.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU05_Recarga_Puntos_BC.md) |
| **CU-06** | Descenso y Desacoplamiento GPS | Pasajero, Backend, GPS Bus | [CU06_Descenso_Desacoplamiento_Geofencing.md](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/CU06_Descenso_Desacoplamiento_Geofencing.md) |

