# Especificación Detallada de Caso de Uso: CU-05
## Recarga de Puntos BC mediante Pasarela Digital
**Documento UML:** `docs/casos_de_uso/CU05_Recarga_Puntos_BC.md`  
**Referencia UML:** `CU05` en [diagrama_casos_de_uso.puml](file:///Users/aron/githubRepo/sem-bus/docs/casos_de_uso/diagrama_casos_de_uso.puml)  
**Versión:** 2.0 (Análisis Riguroso)

---

## 1. Caracterización Formal del Caso de Uso

| Atributo | Definición Formal |
| :--- | :--- |
| **Identificador** | **CU-05** |
| **Nombre** | Recarga de Puntos BC mediante Pasarela Digital |
| **Nivel** | Objetivo de Usuario / Gestión Financiera de Monedero |
| **Actor Primario** | **Pasajero Registrado** |
| **Actores Secundarios** | **Pasarela de Pagos Externa (Yape / Plin / Tarjetas)**, **Sistema Backend BC** |
| **Partes Interesadas** | *Pasajero:* Disponer de saldo suficiente para viajar sin depender de efectivo.<br>*Empresa de Transporte:* Anticipación de flujo de caja (prepago de pasajes) y reducción de manipulación de billetes. |
| **Precondiciones** | El usuario tiene sesión activa en la App BC. Dispone de saldo en su cuenta de ahorros bancaria o billetera digital Yape/Plin. |
| **Postcondición de Éxito** | Se acreditan los Puntos BC según la tasa fija (S/. 1.00 = 10 Pts), se inserta el asiento en `ledger_transactions` y el saldo está listo para usarse. |
| **Postcondición de Falla** | No se debitan fondos bancarios, la orden de recarga expira y el saldo de puntos previo permanece inalterado. |
| **Disparador** | El pasajero presiona el botón *"Recargar Puntos"* en el monedero de la app. |

---

## 2. Puntos de Inclusión (`<<include>>`) y Extensión (`<<extend>>`)

### 2.1. Casos de Uso Incluidos (`<<include>>`)
* **`<<include>> CU-05.1` (Iniciar Intención de Pago Digital):** Creación de la orden transaccional con la pasarela bancaria y obtención del token/referencia de pago.
* **`<<include>> CU-05.2` (Asentar en Libro Mayor - Ledger):** Registro contable inmutable con `balance_before`, `amount_credit` y `balance_after`.

### 2.2. Puntos de Extensión (`<<extend>>`)

```
+---------------------------------------------------------------------------------------------------+
| PUNTO DE EXTENSIÓN 1: [PE-RECHAZO-BANCO] (Fallo en la Transacción Bancaria)                        |
|   Extendido por: CU-05.A (Manejar Rechazo de Fondos Bancarios)                                     |
|   Condición de Activación: Pasarela bancaria retorna error por fondos insuficientes o timeout.   |
+---------------------------------------------------------------------------------------------------+
```

---

## 3. Diagrama de Actividades UML (Flujo de Decisiones)

```mermaid
flowchart TD
    subgraph Pasajero["👤 Pasajero"]
        A1([En Monedero App]) --> A2[Presiona 'Recargar Puntos']
        A2 --> A3[Selecciona monto: S/. 5, S/. 10, S/. 20 o S/. 50]
        A3 --> A4[Selecciona método: Yape / Tarjeta Débito]
        A4 --> A5[Presiona 'Pagar S/. X.00']
    end

    subgraph App["📱 App Móvil Pasajero"]
        A5 --> B1[Valida monto mínimo >= S/. 5.00 y <= S/. 100.00]
        B1 --> B2[Envía POST /api/v1/wallet/recharge/intent]
    end

    subgraph Backend["🖥️ Backend Central BC"]
        B2 --> C1[CU-05.1: Genera orden interna con estado PENDING]
        C1 --> C2[Llama API Pasarela de Pagos]
    end

    subgraph Pasarela["🏦 Pasarela de Pagos (Yape/Niubiz)"]
        C2 --> D1[Crea sesión de pago y devuelve token de SDK/Web]
        D1 --> D2{¿El banco autoriza el cobro?}
        D2 -- No --> D_FAIL[CU-05.A: Error Fondos Insuficientes]
        D2 -- Sí --> D3[Debita cuenta bancaria del usuario]
        D3 --> D4[Envía HTTP Webhook firmado a Backend BC]
    end

    D1 --> B3[App despliega modal seguro de pago de pasarela]
    A5 --> B3

    D4 --> C3[Valida firma criptográfica del Webhook]
    C3 --> C4[Convierte Soles a Puntos: Puntos = PEN * 10]
    C4 --> C5[CU-05.2: Transacción ACID en Libro Mayor Ledger]
    C5 --> C6[Actualiza Users: saldo_puntos = saldo + Puntos]
    C6 --> C7[Emite Push / WebSocket al celular del usuario]

    C7 --> B_OK[App: Muestra animación de recarga exitosa y nuevo saldo]
    D_FAIL --> B_FAIL[App: Notifica rechazo de banco sin alterar saldo]

    B_OK --> END_OK([Fin Exitoso: Saldo listo para viajar])
    B_FAIL --> END_FAIL([Fin con Rechazo: Usuario reintenta o cambia medio])
```

---

## 4. Descripción Paso a Paso del Flujo

1. **[Selección de Monto]:** El usuario abre el monedero en la App BC y selecciona el importe en soles mediante botones rápidos (`S/. 5.00`, `S/. 10.00`, `S/. 20.00`, `S/. 50.00`) o ingresa un monto personalizado (mínimo S/. 5.00, máximo S/. 100.00).
2. **[Selección de Medio de Pago]:** Elige entre:
   * **Yape (Código de Aprobación):** Genera el código de 6 dígitos en Yape y lo ingresa en la app.
   * **Tarjeta Débito/Crédito:** Ingresa datos con tokenización segura PCI-DSS.
3. **[Creación de Intención - Inclusión CU-05.1]:**
   * La app despacha: `POST /api/v1/wallet/recharge/intent { "amount_pen": 10.00, "gateway": "YAPE" }`.
   * El backend crea un registro en tabla `recharges` con estado `PENDING` y expira a los 10 minutos.
4. **[Procesamiento Bancario]:**
   * La pasarela procesa el cobro con el banco emisor.
   * Al completarse, la pasarela dispara un Webhook HTTP seguro hacia el endpoint del backend con firma HMAC-SHA256:
     ```json
     POST /api/v1/webhooks/recharges
     X-Signature: c81a94f...
     {
       "recharge_id": "REC-849102",
       "amount_pen": 10.00,
       "status": "APPROVED",
       "auth_code": "AUT-91820"
     }
     ```
5. **[Asiento en Libro Mayor - Inclusión CU-05.2]:**
   * El backend valida la firma del webhook para impedir falsificaciones.
   * Ejecuta la conversión de moneda: $\text{Puntos} = 10.00 \times 10 = 100\text{ Puntos BC}$.
   * En una transacción atómica:
     * Cambia el estado de la recarga a `COMPLETED`.
     * Inserta en `ledger_transactions` el tipo `RECHARGE_CREDIT`.
     * Incrementa `users.wallet_points += 100`.
6. **[Notificación]:**
   * El backend emite un mensaje por WebSocket a la sesión del usuario.
   * La app vibra suavemente, reproduce un sonido de monedas y actualiza el saldo en pantalla: *"¡Recarga exitosa! +100 Puntos BC añadidos"*.
