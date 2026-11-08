# Proyecto BC - Matriz de Trazabilidad, Reglas de Negocio y Base de Datos
**Ubicación:** `docs/requerimientos/02_Matriz_Trazabilidad_Requerimientos.md`  
**Versión:** 2.3 (Fase 1: MVP - Actualizada tras Auditoría SWEBOK v4)

---

## 1. Matriz de Trazabilidad Integral (Requerimiento ↔ Regla ↔ Caso de Uso ↔ Base de Datos)

| Código Regla | Nombre de la Regla | Requerimiento Asociado | Caso de Uso UML | Tablas BD Relacionadas | Descripción / Comportamiento del Sistema |
| :--- | :--- | :--- | :---: | :--- | :--- |
| **RN-01** | Tarifas Dinámicas Configurables | RF-MON-01, RF-TAR-01 | CU-01, CU-12 | `fare_config` | Adulto: 15 Pts (S/. 1.50). Universitario: 7 Pts (S/. 0.70). CONADIS: 0 Pts. Modificables en caliente por el Administrador. |
| **RN-02** | Monedero Cerrado de Puntos | RF-MON-01, RF-MON-02 | CU-05, CU-08 | `wallets`, `ledger_transactions` | Tasa fija 1 Sol = 10 Puntos. Monedero cerrado de transporte sin intermediación bancaria SBS de dinero abierto. |
| **RN-03** | Tolerancia Cero Saldo Negativo | RF-MON-04 | CU-01.C | `wallets` (CHECK >= 0) | Cero crédito. Si Saldo < Tarifa, rechazo inmediato en POS con tono grave y pantalla roja. |
| **RN-04** | QR Dinámico de Un Solo Uso | RF-POS-01 | CU-01, CU-01.D | `shifts.qr_nonce`, `trips.qr_nonce_used` | Nonce expira tras 1 cobro o 30 segundos de inactividad. Regeneración en < 500 ms tras cobro exitoso. |
| **RN-05** | Failsafe de Pago Yape Directo | RF-POS-02 | CU-02.A | `ledger_transactions` | Espera de webhook bancario por máx. 5 seg. Si expira, habilita validación manual en tablet del chofer. |
| **RN-06** | Cooldown Universitario (120s) | RF-TAR-04 | CU-01.A | `fare_config.student_cooldown_seconds` | Tras cobrar 7 puntos al titular, la tarifa universitaria se bloquea por 2 minutos para evitar préstamo de celular. |
| **RN-07** | Pago Acompañante Regular | RF-TAR-05 | CU-01.B | `trips.companion_count` | Al pulsar `[+]`, todos los pasajes adicionales se liquidan obligatoriamente a tarifa regular de 15 puntos. |
| **RN-08** | Unicidad de Carnet Universitario | RF-TAR-02 | CU-03.2 | `student_verifications` (UNIQUE user_id, DNI) | Un mismo DNI universitario solo puede estar vinculado a una cuenta activa a la vez. |
| **RN-09** | Desacoplamiento GPS (>150m) | RF-GEO-02 | CU-06, CU-06.1 | `trips`, `buses` | Si la distancia entre bus y celular supera 150m en 2 latidos consecutivos (45s), el viaje se finaliza de forma autónoma. |
| **RN-10** | Reembolso por Avería de Unidad | RF-MON-05 | CU-04.A, CU-12 | `trips`, `ledger_transactions` (REFUND_CREDIT) | Chofer o Admin reportan avería; backend devuelve de inmediato el 100% de puntos a pasajeros con viaje activo. |
| **RN-11** | Sesión Única por Dispositivo (Yape) | RF-PAS-02 | CU-00.4 | `users.current_device_id`, `user_sessions` | 1 sola sesión activa por cuenta; el ingreso en nuevo equipo revoca inmediatamente las sesiones previas. |
| **RN-12** | Bloqueo Pesimista en Débito (ACID) | RF-MON-01 | CU-01.1 | `wallets` (`fn_debit_wallet()`) | Durante el cobro, el backend ejecuta `SELECT ... FOR UPDATE` sobre la fila del monedero para evitar doble gasto. |
| **RN-13** | Idempotencia en Webhooks Bancarios | RF-POS-02 | CU-02.1 | `webhook_idempotency` | Verificación de unicidad sobre `(gateway, gateway_tx_id)` para ignorar reintentos y evitar aforos duplicados. |
| **RN-14** | Prórroga Flexible de Carnet SUNEDU | RF-TAR-01 | CU-03, CU-12 | `student_verifications.extension_grace_days`, `app_config` | Parámetro configurable en BD para extender la vigencia ante decretos oficiales extraordinarios de prórroga. |
| **RN-15** | Sentido Fijo y Pausa en Mapa Público | RF-CON-01 | CU-04.C, CU-12.C | `buses.is_visible_public`, `buses.current_direction` | Inversión automática de sentido al llegar a terminal y botón de pausa para ocultar bus a pasajeros ante pinchazos. |
| **RN-16** | Emparejamiento Seguro de Hardware | RF-POS-03 | CU-10 | `hardware_pairings`, `buses` | POS y Tablet se vinculan al bus mediante token QR de un solo uso generado por el Administrador con certificados mTLS. |
| **RN-17** | Derecho al Olvido y Baja de Cuenta | RF-PAS-04 | CU-11, CU-11.4 | `users.is_active`, `user_sessions` | Proceso autónomo de eliminación de cuenta con advertencia de saldo, revocación de sesiones y anonimización a 15 días (Apple/Google). |
| **RN-18** | Gestión y Auditoría Centralizada | RF-ADM-01 | CU-12 | `app_config`, `fare_config`, `v_buses_realtime` | Consola Backoffice para supervisión global de flota, cambios de parámetros en caliente y auditoría de recaudación. |

---

## 2. Matriz de Estados de Error y Mecanismos de Mitigación

| Escenario de Excepción | Impacto Potencial | Detección / Condición | Acción / Mitigación del Sistema | Caso de Uso |
| :--- | :--- | :--- | :--- | :---: |
| **Saldo insuficiente en puerta** | Retraso en cola de abordaje. | `saldo_usuario < tarifa` al escanear. | POS emite `BEEP-BEEP` rojo y muestra saldo faltante. Pasajero debe pagar con Yape directo o apartarse. | CU-01.C |
| **Caída temporal de señal 4G en el bus** | Imposibilidad de validar pagos online. | Timeout de conexión en POS (> 3 seg). | POS muestra pantalla de contingencia *"Reconectando 4G"*. Chofer puede autorizar paso visualmente. | CU-01 |
| **Demora de webhook bancario (Yape)** | Pasajero esperando en el pasillo. | Webhook no llega en 5 segundos. | Tablet del chofer habilita botón `[Validar Manualmente]` previa vista del voucher oficial en el cel del usuario. | CU-02.A |
| **Usuario cierra la app durante el viaje** | Viaje queda abierto indefinidamente. | App no envía latidos GPS de fondo. | El viaje se cierra automáticamente cuando el bus llega al terminal o tras 60 minutos de viaje acumulado. | CU-06.B |
| **Carnet universitario vencido** | Usuario intenta pagar 7 puntos. | `fecha_actual > fecha_caducidad_sunedu`. | La app muestra aviso de caducidad y liquida el viaje automáticamente a tarifa regular de 15 puntos. | CU-03.B |
| **Dos usuarios escanean a la vez** | Confusión sobre quién pagó. | Dos lecturas simultáneas del mismo QR. | El primer request en llegar procesa el pago; el segundo recibe error *"QR expirado"* y el POS ya muestra el nuevo QR. | CU-01.D |
| **Desinstalación de app durante viaje** | Sesión huérfana sin pings de GPS. | No hay latidos GPS tras 5 minutos. | Se activa failsafe de fin de trayecto al llegar al terminal o tras 60 min sin penalidades para el usuario. | CU-06 |
| **Robo o extravío de Tablet/POS** | Riesgo de emisión de transacciones falsas. | Admin reporta hardware comprometido. | Admin revoca el hardware desde Backoffice en < 1 seg invalidando mTLS/JWT y bloqueando el equipo. | CU-10.A, CU-12 |
