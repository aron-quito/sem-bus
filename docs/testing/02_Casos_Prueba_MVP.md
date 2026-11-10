# Catálogo de Casos de Prueba del MVP (Sprints 1 a 4)
## Sistema BC (Bus Conectado) — Transporte Urbano Automatizado (Tacna, Perú)

> **Documento:** `docs/testing/02_Casos_Prueba_MVP.md`  
> **Versión:** 1.0 (Noviembre 2026)  
> **Estándar:** SWEBOK v4 / Casos de Prueba Derivados de Criterios BDD

---

## 1. Módulo: Autenticación y Onboarding (CU-00)

### TC-AUTH-01: Registro Exitoso con Celular Peruano Válido
* **CU Asociado:** CU-00
* **Prioridad:** P1 (Bloqueante)
* **Automatizable:** Sí (Maestro E2E / Pytest)
* **Precondiciones:** Dispositivo con app instalada y conexión a internet; número `952123456` sin cuenta previa.
* **Pasos:**
  1. Abrir la app e ingresar al flujo de autenticación.
  2. Digitar `952123456` en el campo telefónico y pulsar *"Continuar"*.
  3. Ingresar el código OTP recibido (`123456`).
* **Resultado Esperado:** Cuenta creada con rol `PASSENGER`, monedero inicializado en `0 Puntos BC`, Access Token JWT emitido y redirección a la pantalla de bienvenida.
* **Estado:** ⬜ Pendiente de Ejecución

### TC-AUTH-02: Rechazo de Formato Telefónico Inválido
* **CU Asociado:** CU-00
* **Prioridad:** P2 (Crítico)
* **Automatizable:** Sí (Unitario / E2E)
* **Pasos:** Ingresar números como `852123456` (no inicia en 9) o `9521234` (7 dígitos).
* **Resultado Esperado:** El botón de envío permanece deshabilitado y se muestra el mensaje de error: *"Ingresa un número de 9 dígitos que empiece con 9"*.
* **Estado:** ⬜ Pendiente de Ejecución

### TC-AUTH-03: Bloqueo Anti-Fuerza Bruta tras 3 Intentos Fallidos
* **CU Asociado:** CU-00
* **Prioridad:** P1 (Seguridad)
* **Pasos:** Ingresar 3 códigos OTP erróneos seguidos en menos de 10 minutos.
* **Resultado Esperado:** El backend rechaza intentos con código HTTP 429 y bloquea solicitudes para ese número durante 10 minutos.
* **Estado:** ⬜ Pendiente de Ejecución

### TC-AUTH-04: Sesión Única por Dispositivo (Estilo Yape)
* **CU Asociado:** CU-00 (Inclusión CU-00.4)
* **Prioridad:** P1 (Seguridad)
* **Precondiciones:** Usuario con sesión activa en Dispositivo A.
* **Pasos:** Iniciar sesión exitosamente con el mismo número en el Dispositivo B.
* **Resultado Esperado:** Dispositivo B obtiene acceso pleno; Dispositivo A recibe revocado de token en el siguiente request y muestra: *"Tu sesión se ha abierto en otro dispositivo"*.
* **Estado:** ⬜ Pendiente de Ejecución

---

## 2. Módulo: Pago de Pasaje y Abordaje (CU-01 / CU-02)

### TC-PAY-01: Pago Exitoso con Tarifa General Regular (15 Puntos)
* **CU Asociado:** CU-01
* **Prioridad:** P1 (Financiero)
* **Precondiciones:** Usuario adulto con saldo de 85 puntos en monedero.
* **Pasos:**
  1. Abrir pestaña *"Pagar QR"*.
  2. Apuntar la cámara al QR dinámico del validador de `BUS 01`.
* **Resultado Esperado:** 
  1. Débito atómico de exactamente 15 puntos (S/. 1.50).
  2. Saldo restante = 70 puntos.
  3. Feedback sonoro de 880Hz y vibración háptica.
  4. Tablet del chofer despliega tarjeta esmeralda `"Pasaje Adulto S/. 1.50"`.
* **Estado:** ⬜ Pendiente de Ejecución

### TC-PAY-02: Pago con Beneficio Universitario SUNEDU (7 Puntos)
* **CU Asociado:** CU-01 / CU-03
* **Prioridad:** P1 (Financiero)
* **Precondiciones:** Alumno con carné universitario vigente acreditado en perfil y 85 puntos de saldo.
* **Pasos:** Escanear el QR de abordaje.
* **Resultado Esperado:** Débito de 7 puntos (S/. 0.70); saldo remanente = 78 puntos; tablet del chofer muestra tarjeta ámbar `"UNIV S/. 0.70"`.
* **Estado:** ⬜ Pendiente de Ejecución

### TC-PAY-03: Rechazo Absoluto por Saldo Insuficiente (Cero Saldo Negativo)
* **CU Asociado:** CU-01 (RN-04)
* **Prioridad:** P1 (Bloqueante Financiero)
* **Precondiciones:** Usuario con saldo = 5 puntos.
* **Pasos:** Intentar pagar pasaje general (15 pts).
* **Resultado Esperado:** Validador emite tono grave de rechazo; modal en app despliega *"Saldo Insuficiente"* con botón para recargar; el saldo permanece inalterado en 5 puntos (cero saldo negativo).
* **Estado:** ⬜ Pendiente de Ejecución

### TC-PAY-04: Rechazo de Código QR Expirado (>30 Segundos)
* **CU Asociado:** CU-01 (RN-01)
* **Prioridad:** P2 (Seguridad Anti-Captura)
* **Pasos:** Escanear una captura de pantalla de un QR emitido hace más de 30 segundos.
* **Resultado Esperado:** Rechazo inmediato por el backend: *"Código QR vencido"*; no se debita saldo.
* **Estado:** ⬜ Pendiente de Ejecución

### TC-PAY-05: Pago con Acompañantes Múltiples
* **CU Asociado:** CU-01 (RN-07)
* **Precondiciones:** Estudiante (7 pts) viaja con 2 amigos acompañantes.
* **Pasos:** Seleccionar selector de acompañantes `[+2]` y escanear QR.
* **Resultado Esperado:** Débito de $7 + 15 + 15 = 37$ puntos; los acompañantes pagan tarifa completa obligatoria.
* **Estado:** ⬜ Pendiente de Ejecución

---

## 3. Módulo: Monedero BC y Recargas (CU-05 / CU-08)

### TC-WAL-01: Recarga Exitosa de 10 Soles vía Yape Webhook
* **CU Asociado:** CU-05
* **Prioridad:** P1 (Financiero)
* **Pasos:** Simular recepción de webhook firmado de Yape por S/. 10.00 asociado a la orden del usuario.
* **Resultado Esperado:** El libro mayor ejecuta `fn_credit_wallet` y acredita exactamente 100 Puntos BC (paridad 1 PEN = 10 pts).
* **Estado:** ⬜ Pendiente de Ejecución

### TC-WAL-02: Integridad Inmutable del Historial de Movimientos
* **CU Asociado:** CU-08
* **Pasos:** Consultar `GET /api/v1/wallet/history`.
* **Resultado Esperado:** Lista cronológicamente descendente con fechas, identificador de unidad, monto debitado/acreditado y estado completado.
* **Estado:** ⬜ Pendiente de Ejecución

---

## 4. Módulo: Telemetría GPS y Geofencing (CU-06 / CU-07)

### TC-GPS-01: Transmisión Continua de Coordenadas vía WebSocket
* **CU Asociado:** CU-07
* **Pasos:** Conectar cliente WebSocket al canal `bus/1/position`.
* **Resultado Esperado:** Recepción de coordenadas cada 3 a 5 segundos con latencia inferior a 250 ms.
* **Estado:** ⬜ Pendiente de Ejecución

### TC-GPS-02: Alarma Sonora de Desembarque a 400 Metros
* **CU Asociado:** CU-06
* **Precondiciones:** Pasajero en viaje con destino fijado en *"Mercadillo Bolognesi"*.
* **Pasos:** Simular avance del bus hasta posicionarse a 390 metros del paradero objetivo.
* **Resultado Esperado:** La app dispara melodía sonora melódica de 4 tonos y notificación háptica de proximidad.
* **Estado:** ⬜ Pendiente de Ejecución

### TC-GPS-03: Desacoplamiento Automático por Geofencing (>150 Metros)
* **CU Asociado:** CU-06 (RN-09)
* **Pasos:** Simular alejamiento del pasajero >150m del bus durante más de 30 segundos.
* **Resultado Esperado:** Cierre automático del viaje en curso y retiro de la Live Activity.
* **Estado:** ⬜ Pendiente de Ejecución

---

## 5. Módulo: Conductor y Contingencias (CU-04)

### TC-DRV-01: Registro de Pasajero CONADIS sin Cargo Financiero
* **CU Asociado:** CU-04 / RF-TAR-06
* **Pasos:** Chofer presiona botón `[+1 CONADIS]` en la tablet de cabina.
* **Resultado Esperado:** El contador de aforo se incrementa en +1 pasajero; monto financiero registrado = S/. 0.00.
* **Estado:** ⬜ Pendiente de Ejecución

### TC-DRV-02: Declaración de Avería y Reembolso Automático de Puntos
* **CU Asociado:** CU-04 (RF-MON-05)
* **Precondiciones:** `BUS 01` transporta 12 pasajeros con viaje activo.
* **Pasos:** Chofer confirma `[Avería de Unidad]` en la tablet.
* **Resultado Esperado:** Todos los 12 pasajeros reciben reembolso íntegro de sus puntos debitados y notificación push inmediata.
* **Estado:** ⬜ Pendiente de Ejecución
