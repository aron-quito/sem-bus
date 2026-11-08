# Especificación Detallada de Caso de Uso: CU-03
## Acreditación de Carnet Universitario (SUNEDU)
**Documento UML:** `docs/casos_de_uso/CU03_Acreditacion_Carnet_SUNEDU.md`  
**Referencia UML:** `CU03` en [diagrama_casos_de_uso.puml](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/diagrama_casos_de_uso.puml)  
**Versión:** 2.0 (Análisis Riguroso)

---

## 1. Caracterización Formal del Caso de Uso

| Atributo | Definición Formal |
| :--- | :--- |
| **Identificador** | **CU-03** |
| **Nombre** | Acreditación y Validación de Tarifa Universitaria con QR SUNEDU |
| **Nivel** | Proceso de Soporte / Gestión de Beneficios Tarifarios |
| **Actor Primario** | **Pasajero Estudiante Universitario** |
| **Actores Secundarios** | **Servicio de Validación SUNEDU**, **Administrador de Transporte (Auditor)**, **Sistema Backend BC** |
| **Partes Interesadas** | *Estudiante:* Obtener la tarifa preferencial legal (S/. 0.70 por viaje).<br>*Empresa de Transporte:* Asegurar que solo estudiantes con carnet legítimo y vigente gocen del descuento, evitando fraudes de carnets prestados o falsificados. |
| **Precondiciones** | El usuario tiene cuenta activa en la App BC. Dispone del carnet universitario físico emitido por SUNEDU. |
| **Postcondición de Éxito** | El rol de la cuenta se actualiza a `STUDENT`, se programa la fecha de caducidad automática del beneficio y se habilita la tarifa de 7 Puntos BC. |
| **Postcondición de Falla** | La cuenta permanece en rol `ADULT` (tarifa 15 puntos) con notificación detallada de la causa de rechazo. |
| **Disparador** | El estudiante selecciona *"Vincular Carnet Universitario"* en su perfil de la App BC. |

---

## 2. Diagrama UML de Casos de Uso (Estructura y Relaciones)

<div align="center">
  <img src="CU03_Acreditacion_Carnet_SUNEDU.png" alt="Diagrama UML de Casos de Uso - CU-03: Acreditación de Carnet Universitario (SUNEDU)" style="max-width: 100%; height: auto; border: 1px solid #d1d5db; border-radius: 8px; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);" />
  <p><em>Figura: Diagrama UML 2.5 del Caso de Uso con Actores, Caso Base, relaciones &laquo;include&raquo; y &laquo;extend&raquo;.</em></p>
</div>

## 3. Puntos de Inclusión (`<<include>>`) y Extensión (`<<extend>>`)

### 2.1. Casos de Uso Incluidos (`<<include>>`)
* **`<<include>> CU-03.1` (Decodificar y Validar QR Oficial SUNEDU):** Lectura del formato criptográfico oficial impreso en el carnet, extrayendo DNI, universidad y fecha de caducidad.
* **`<<include>> CU-03.2` (Verificar Unicidad de DNI en Sistema):** Consulta a la base de datos para garantizar que ese DNI no esté registrado en otra cuenta activa.

### 2.2. Puntos de Extensión (`<<extend>>`)

```
+---------------------------------------------------------------------------------------------------+
| PUNTO DE EXTENSIÓN 1: [PE-CALIDAD-QR] (Carnet Deteriorado o Ilegible)                              |
|   Extendido por: CU-03.A (Derivar a Cola de Auditoría Manual Web)                                 |
|   Condición de Activación: La cámara falla al decodificar el QR tras 2 intentos consecutivos.     |
+---------------------------------------------------------------------------------------------------+
| PUNTO DE EXTENSIÓN 2: [PE-VIGENCIA] (Carnet Vencido en Fecha)                                     |
|   Extendido por: CU-03.B (Rechazar por Caducidad Vencida)                                         |
|   Condición de Activación: fecha_caducidad_sunedu < fecha_actual                                  |
+---------------------------------------------------------------------------------------------------+
```

---

## 3. Diagrama de Actividades UML




 (Flujo de Decisiones)

```mermaid
flowchart TD
    subgraph Estudiante["🎓 Pasajero Estudiante"]
        A1([Inicio: En Perfil App]) --> A2[Presiona 'Activar Tarifa Universitaria']
        A2 --> A3[Apunta cámara al QR del carnet físico]
    end

    subgraph App["📱 App Móvil Pasajero"]
        A3 --> B1{¿Cámara leyó el QR con éxito?}
        B1 -- No (2 intentos) --> B_EXT_A[CU-03.A: Solicita fotos del carnet]
        B1 -- Sí --> B2[CU-03.1: Parsea Payload SUNEDU]
        B2 --> B3[Solicita captura de foto del anverso carnet]
        B3 --> B4[Envía POST /api/v1/students/verify]
    end

    subgraph Backend["🖥️ Backend Central BC"]
        B4 --> C1[CU-03.2: Consulta DNI en tabla 'student_verifications']
        C1 --> C2{¿DNI ya registrado en otra cuenta activa?}
        C2 -- Sí (Fraude) --> C_ERR_DUP[Rechazo: DNI ya vinculado a otra cuenta]
        C2 -- No --> C3[Evalúa fecha de caducidad oficial]
        
        C3 --> C4{¿fecha_caducidad >= Fecha Actual?}
        C4 -- No --> C_EXT_B[CU-03.B: Rechazo: Carnet Vencido]
        C4 -- Sí --> C5[Almacena foto de respaldo en S3/Storage]
        C5 --> C6[Actualiza User: rol='STUDENT', expires_at=caducidad]
        C6 --> C7[Programa Cron Job para revocación al vencer]
        C7 --> C8[Retorna 200 OK con Insignia Estudiante]
    end

    subgraph Admin["👨‍💻 Auditoría Manual (Web Admin)"]
        B_EXT_A --> D1[Pasajero sube fotos frente y reverso]
        D1 --> D2[Ingresa a cola 'Pendientes de Revisión']
        D2 --> D3{¿Auditor aprueba carnet manual?}
        D3 -- Sí --> C6
        D3 -- No --> D_REJ[Notifica rechazo con motivo al alumno]
    end

    C8 --> B_OK[App: Muestra insignia dorada 'Tarifa S/. 0.70 Activada']
    C_ERR_DUP --> B_ERR1[App: Error DNI duplicado]
    C_EXT_B --> B_ERR2[App: Error Carnet vencido]
    D_REJ --> B_ERR3[App: Solicitud manual rechazada]

    B_OK --> END_OK([Fin Exitoso: Tarifa activa por máx 1 año])
    B_ERR1 --> END_FAIL([Fin con Rechazo: Permanece en tarifa adulto])
    B_ERR2 --> END_FAIL
    B_ERR3 --> END_FAIL
```

---

## 4. Descripción Paso a Paso del Flujo

1. **[Inicio]:** El estudiante accede a la pestaña de perfil en la App BC y selecciona el banner *"Activar Tarifa Universitaria (S/. 0.70)"*.
2. **[Lectura de QR - Inclusión CU-03.1]:**
   * La app activa la cámara con un visor específico para el formato QR de SUNEDU.
   * El estudiante enfoca el código QR ubicado al dorso del carnet.
   * La app decodifica la cadena oficial:
     ```
     SUNEDU|DNI:74819201|UNIV:UNJBG|ALUMNO:QUISPE MAMANI ARON|VENC:30/04/2027
     ```
3. **[Captura de Evidencia]:** La app solicita inmediatamente una fotografía nítida del anverso del carnet físico (donde se visualiza el rostro y nombre del estudiante).
4. **[Envío Seguro al Backend]:** La app empaqueta la información y la fotografía en base64:
   ```json
   POST /api/v1/students/verify
   {
     "dni": "74819201",
     "university": "UNJBG",
     "expires_at": "2027-04-30T23:59:59Z",
     "card_photo": "data:image/jpeg;base64,..."
   }
   ```
5. **[Verificación de Unicidad - Inclusión CU-03.2]:**
   * El backend busca en la base de datos: `SELECT user_id FROM student_verifications WHERE dni = '74819201' AND status = 'ACTIVE'`.
   * Si ya existe un registro con un `user_id` diferente, aborta la operación con `409 Conflict: STUDENT_CARD_ALREADY_REGISTERED`.
6. **[Validación de Caducidad con Prórroga Oficial SUNEDU]:**
   * El backend evalúa la fecha oficial del plástico sumando el parámetro global configurable:  
     `fecha_limite = expires_at + INTERVAL 'extension_gracia_dias' DAY`.  
     *(Permite que, ante decretos de prórroga oficial de SUNEDU en Perú, el administrador configure 30 o 60 días adicionales sin que los estudiantes pierdan su beneficio).*
   * Si `NOW() > fecha_limite`, activa la extensión **CU-03.B** y rechaza la postulación.
7. **[Activación del Beneficio]:**
   * Actualiza el perfil del usuario: `role = 'STUDENT'`, `student_expires_at = '2027-04-30'`.
   * Registra la evidencia en el bucket de almacenamiento seguro.
   * Programa una tarea diferida (cron job) para el día `2027-05-01` a las 00:00 para revertir automáticamente el rol a `ADULT`.
8. **[Confirmación]:** La app despliega una animación de éxito con la insignia dorada *"Estudiante Verificado"* y en su monedero se actualiza el costo por pasaje a **7 Puntos BC (S/. 0.70)**.
