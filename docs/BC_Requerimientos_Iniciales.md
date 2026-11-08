# Proyecto BC (Bus Conectado / Sistema de Buses Automatizado)
## Documento de Especificación Inicial de Requerimientos (SRS preliminar)
**Fecha:** Noviembre 2026  
**Ubicación / Contexto:** Tacna, Perú  
**Estado:** Borrador de Análisis (Fase 1: Levantamiento y Refinamiento)

---

## 1. Visión del Producto
El proyecto **BC** es un ecosistema tecnológico integral de transporte público orientado a modernizar y automatizar el abordaje, cobro de pasajes, monitoreo de flotas y experiencia del usuario en buses urbanos.

El ecosistema se compone de 3 subsistemas principales:
1. **Aplicativo Móvil del Pasajero (iOS / Android):** Para consulta de rutas en vivo, saldo prepago, pagos automáticos y validación de beneficios (universitario, escolar, etc.).
2. **Módulo Validador de a Bordo (POS / Hardware en Bus):** Dispositivo instalado en el ingreso del bus con cámara (escaneo QR), lector NFC, pantalla dual o interfaz informativa para el pasajero y el conductor.
3. **Plataforma Central / Backend y Telemetría:** Motor de geolocalización de buses en tiempo real, administración de tarifas, pasarela de recargas y gestión de flotas.

---

## 2. Actores del Sistema

| Actor | Descripción |
| :--- | :--- |
| **Pasajero Anónimo (Invitado)** | Usuario que descarga la app y la usa sin registrarse para consultar rutas y ubicación de buses en tiempo real. |
| **Pasajero Registrado (Adulto)** | Usuario con cuenta verificada por celular, con billetera de saldo/puntos recargable mediante Yape/Plin/Tarjetas. Tarifa estándar. |
| **Pasajero Estudiante / Universitario** | Usuario registrado con carnet universitario verificado vigente (validez máx. 1 año). Accede a tarifa preferencial (S/. 0.70). |
| **Pasajero CONADIS** | Usuario con carnet de discapacidad. Pasa sin cobro tras validación visual/digital. |
| **Conductor** | Opera la unidad y recibe alertas visuales y/o sonoras en tiempo real sobre el estado de cada pago al momento de subir ("Éxito: Pasó", "Déjalo pasar", etc.). |
| **Administrador / Operador de Ruta** | Supervisa la flota, recaudación, métricas de ocupación y vigencia de beneficios. |

---

## 3. Matriz de Requerimientos Funcionales Iniciales (RF)

### 3.1. Gestión de Usuarios y Accesos
* **RF-01 (Modo Invitado):** La aplicación debe permitir navegación completa del mapa y rutas sin solicitar inicio de sesión ni registro.
* **RF-02 (Registro por Teléfono):** El usuario debe poder registrarse autenticando su número de teléfono móvil (ej. OTP SMS/WhatsApp).
* **RF-03 (Inicio de Sesión):** El usuario registrado debe poder iniciar sesión de forma segura y persistente.
* **RF-04 (Vigencia de Carnet Universitario):** El sistema debe permitir subir la acreditación de carnet universitario, asignar una vigencia máxima de 1 año y revocar el beneficio automáticamente al expirar si no es renovado.

### 3.2. Rutas y Monitoreo en Tiempo Real
* **RF-05 (Visualización de Rutas):** Usuarios anónimos y registrados deben poder visualizar el trazado geométrico completo de las rutas de buses en el mapa.
* **RF-06 (Ubicación en Tiempo Real de Buses):** Usuarios anónimos y registrados deben poder ver la ubicación exacta y en movimiento de las unidades que están operando la ruta.
* **RF-07 (Suscripción a Ruta en Viaje):** Al realizar el pago de pasaje desde la app, el sistema debe "suscribir" automáticamente al pasajero a la unidad/ruta abordada.
* **RF-08 (Desuscripción Automática por Geofencing):** El sistema debe detectar la trayectoria del bus y el descenso del usuario en un paradero para finalizar el viaje y desuscribirlo automáticamente.

### 3.3. Pagos, Saldos y Tarifas
* **RF-09 (Monedero Prepago / Recargas):** El usuario debe poder recargar saldo o puntos en la app mediante pasarelas locales (Yape, Plin, tarjetas de débito/crédito).
* **RF-10 (Tarifario Diferenciado):**
  * Tarifa General Adulto: Tarifa base regular (S/. 1.00 o S/. 1.50 según definición comercial).
  * Tarifa Universitaria: Tarifa reducida a S/. 0.70 por viaje.
  * Tarifa CONADIS: Tarifa exonerada (S/. 0.00).
* **RF-11 (Pago Digital a Bordo - Con App):** El usuario con saldo puede validar su viaje en el módulo del bus (vía QR dinámico en pantalla o NFC).
* **RF-12 (Pago Digital a Bordo - Sin App):** El módulo del bus debe permitir pagos directos para usuarios sin la app instalada (lectura directa de NFC bancario o escaneo de QR Yape/Plin en el POS).

### 3.4. Módulo Validador en Bus (POS)
* **RF-13 (Feedback al Pasajero):** Pantalla o indicación auditiva/visual con mensaje de confirmación de pago ("Éxito", saldo restante, tarifa aplicada).
* **RF-14 (Feedback al Chofer):** Notificación inmediata para el chofer ("El usuario pagó - Déjalo pasar", "Universitario", "CONADIS").
* **RF-15 (Tolerancia Offline / Sincronización):** El POS debe registrar validaciones incluso en zonas con pérdida temporal de cobertura celular y sincronizar cuando recupere señal.

---

## 4. Requerimientos No Funcionales (RNF)
* **RNF-01 (Latencia de Validación):** El proceso de lectura y autorización en el POS al momento de subir debe completarse en **menos de 1.2 segundos** para no retrasar el flujo de pasajeros en la puerta.
* **RNF-02 (Consumo de Datos en Móvil):** La telemetría en tiempo real de la app debe optimizarse (WebSockets / MQTT / Protobuf) para no drenar la batería ni el plan de datos del usuario.
* **RNF-03 (Seguridad contra Fraude de Pantallazos):** Los códigos QR de cobro en la app deben ser dinámicos con refresco cada 15-30 segundos para evitar clonación de pasajes mediante capturas de pantalla.

