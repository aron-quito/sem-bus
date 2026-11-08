# Caso de Uso: CU-05 Recarga de Puntos BC
**Ubicación:** `docs/casos_de_uso/CU05_Recarga_Puntos_BC.md`  
**Módulos Involucrados:** App Móvil Pasajero, Pasarela de Pagos Digital (Culqi / Niubiz / MercadoPago), Backend BC  

---

## 1. Ficha del Caso de Uso

| Atributo | Detalle |
| :--- | :--- |
| **Identificador** | **CU-05** |
| **Nombre** | Recarga de Puntos BC mediante Pasarela Digital |
| **Actores** | Pasajero (Iniciador), Pasarela de Pagos (Yape / Plin / Tarjeta), Backend Central BC |
| **Propósito** | Acreditar Puntos BC en el monedero digital del usuario mediante el pago en soles con Yape, Plin o tarjetas de débito/crédito para permitir viajes futuros. |
| **Precondiciones** | El usuario tiene sesión iniciada en la App BC. Dispone de saldo en su cuenta bancaria o billetera digital. |
| **Disparador** | El usuario presiona el botón *"Recargar Puntos"* en la pantalla de inicio o monedero de la app. |

---

## 2. Flujo Principal (Camino Feliz)

```mermaid
sequenceDiagram
    autonumber
    actor Pasajero
    participant App as App Móvil Pasajero
    participant Backend as Backend Central BC
    participant Pasarela as Pasarela de Pagos (Yape/Tarjetas)

    Pasajero->>App: Selecciona monto a recargar (ej. S/. 10.00 = 100 Puntos)
    Pasajero->>App: Selecciona método de pago (Yape / Tarjeta)
    App->>Backend: POST /api/v1/wallet/recharge/intent { amount_pen: 10.00, method: "YAPE" }
    Backend->>Pasarela: Crea orden de pago digital
    Pasarela-->>Backend: Devuelve token de pago / QR o SDK session
    Backend-->>App: Renderiza flujo de pago en app (ej. código de aprobación Yape)
    Pasajero->>App: Ingresa código de aprobación de Yape y confirma
    App->>Pasarela: Procesa el cobro
    Pasarela->>Backend: Webhook HTTP POST /webhooks/payment { status: "APPROVED", amount: 10.00, ext_tx_id }
    Backend->>Backend: Convierte S/. 10.00 a 100 Puntos BC
    Backend->>Backend: Acredita puntos en monedero y registra en Libro Mayor (Ledger)
    Backend-->>App: Push / WS { event: "RECHARGE_SUCCESS", new_balance: 130 }
    App->>Pasajero: Muestra pantalla de felicitación con nuevo saldo disponible
```

---

## 3. Flujos Alternativos y Excepciones

### 3.1. Flujo Alternativo A: Rechazo por Fondos Insuficientes en el Banco
* **Condición:** La tarjeta bancaria o cuenta Yape del usuario no tiene fondos suficientes.
* **Comportamiento:**
  1. La pasarela bancaria retorna error `PAYMENT_DECLINED`.
  2. La App BC muestra: *"Tu banco no pudo procesar el pago. Por favor verifica tu saldo en Yape o intenta con otra tarjeta"*.
  3. No se acreditan puntos ni se generan cargos en el monedero.

### 3.2. Flujo Alternativo B: Abandono / Cancelación por el Usuario
* **Condición:** El usuario cierra la pantalla de pasarela antes de ingresar el código o confirmar.
* **Comportamiento:**
  1. La orden de recarga expira a los 10 minutos en el backend con estado `EXPIRED`.
  2. El saldo previo del usuario permanece inalterado.

---

## 4. Postcondiciones
* Saldo de Puntos BC incrementado de forma inmediata e inmutable.
* Comprobante digital de recarga almacenado en el historial de transacciones del usuario.
* Tasa de conversión respetada: 1 Sol = 10 Puntos BC.

