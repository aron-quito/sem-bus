# Proyecto BC - Matriz de Trazabilidad, Reglas y Estados de Excepción
**Ubicación:** `docs/requerimientos/02_Matriz_Trazabilidad_Requerimientos.md`  
**Versión:** 2.0 (Fase 1: MVP)

---

## 1. Matriz de Reglas de Negocio vs. Requerimientos

| Código Regla | Nombre de la Regla | Requerimiento Asociado | Descripción / Comportamiento del Sistema |
| :--- | :--- | :--- | :--- |
| **RN-01** | Tarifas Dinámicas Configurables | RF-MON-01, RF-TAR-01 | Adulto: 15 Pts (S/. 1.50). Universitario: 7 Pts (S/. 0.70). CONADIS: 0 Pts. Modificables desde BD/Admin. |
| **RN-02** | Monedero Cerrado de Puntos | RF-MON-01, RF-MON-02 | Moneda interna de transporte. Tasa fija 1 Sol = 10 Puntos. Sin regulación bancaria de dinero electrónico libre. |
| **RN-03** | Tolerancia Cero Saldo Negativo | RF-MON-04 | No existe viaje a crédito. Si Saldo < Tarifa, rechazo inmediato en POS con tono sonoro grave y luz roja. |
| **RN-04** | QR Dinámico de Un Solo Uso | RF-POS-01 | El QR del POS expira tras 1 uso o tras 30 seg de inactividad. Regeneración en < 500 ms tras cobro exitoso. |
| **RN-05** | Failsafe de Pago Yape Directo | RF-POS-02 | Espera confirmación de webhook bancario por máx. 5 seg. Si expira, permite autorización manual en tablet del chofer. |
| **RN-06** | Cooldown Universitario (120 seg) | RF-TAR-04 | Tras pagar 7 puntos, la tarifa universitaria queda bloqueada para la cuenta por 2 minutos (antifraude de préstamo de cel). |
| **RN-07** | Pago Acompañante Regular | RF-TAR-05 | Al usar `[+]` para pagar por amigos, todos los pasajes adicionales se liquidan obligatoriamente a tarifa regular (15 pts). |
| **RN-08** | Unicidad de Carnet Universitario | RF-TAR-02 | Un DNI universitario solo puede asociarse a una cuenta activa a la vez. |
| **RN-09** | Desacoplamiento de Viaje (>150m) | RF-GEO-02 | Si la distancia entre el bus y el celular supera 150m en 2 latidos consecutivos, el backend cierra el viaje. |
| **RN-10** | Reembolso por Avería de Unidad | RF-MON-05 | Si el chofer declara avería en su tablet, todos los pasajeros suscritos reciben la devolución íntegra de sus puntos. |
| **RN-11** | Sesión Única por Dispositivo (Yape) | RF-PAS-02 | Un usuario solo puede tener 1 sesión activa; el inicio en un nuevo equipo revoca inmediatamente la sesión anterior. |
| **RN-12** | Bloqueo Pesimista en Débito (ACID) | RF-MON-01 | Durante el cobro, el backend ejecuta `SELECT ... FOR UPDATE` sobre la fila del monedero para evitar doble gasto. |
| **RN-13** | Idempotencia en Webhooks Bancarios | RF-POS-02 | Comprobación de unicidad sobre `transaction_id` bancario para ignorar reintentos y evitar aforos duplicados. |
| **RN-14** | Prórroga Flexible de Carnet SUNEDU | RF-TAR-01 | Parámetro `extension_gracia_dias` en base de datos para extender beneficios ante decretos oficiales extraordinarios. |
| **RN-15** | Sentido Fijo y Pausa en Mapa Público | RF-CON-01 | Inversión automática de sentido al llegar a cabecera y botón de pausa para ocultar bus de pasajeros ante pinchazos. |
| **RN-16** | Emparejamiento Criptográfico de Hardware | RF-POS-03 | POS y Tablet se vinculan al bus mediante token QR de un solo uso generado por el Administrador en Backoffice. |

---

## 2. Matriz de Estados de Error y Mecanismos de Mitigación

| Escenario de Excepción | Impacto Potencial | Detección / Condición | Acción / Mitigación del Sistema |
| :--- | :--- | :--- | :--- |
| **Saldo insuficiente en puerta** | Retraso en cola de abordaje. | `saldo_usuario < tarifa` al escanear. | POS emite `BEEP-BEEP` rojo y muestra saldo faltante. Pasajero debe pagar con Yape directo o apartarse. |
| **Caída temporal de señal 4G en el bus** | Imposibilidad de validar pagos online. | Timeout de conexión en POS (> 3 seg). | POS muestra pantalla de contingencia *"Reconectando 4G"*. Chofer puede autorizar paso visualmente. |
| **Demora de webhook bancario (Yape)** | Pasajero esperando en el pasillo. | Webhook no llega en 5 segundos. | Tablet del chofer habilita botón `[Validar Manualmente]` previa vista del voucher oficial en el cel del usuario. |
| **Usuario cierra la app durante el viaje** | Viaje queda abierto indefinidamente. | App no envía latidos GPS de fondo. | El viaje se cierra automáticamente cuando el bus llega al terminal o tras 60 minutos de viaje acumulado. |
| **Carnet universitario vencido** | Usuario intenta pagar 7 puntos. | `fecha_actual > fecha_caducidad_sunedu`. | La app muestra aviso de caducidad y liquida el viaje automáticamente a tarifa regular de 15 puntos. |
| **Dos usuarios escanean a la vez** | Confusión sobre quién pagó. | Dos lecturas simultáneas del mismo QR. | El primer request en llegar al servidor procesa el pago; el segundo recibe error *"QR expirado"* y el POS ya muestra el nuevo QR. |

