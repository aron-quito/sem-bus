# Bus Conectado • Terminal Cabina Conductor (`driver-web`)

Aplicación web táctil autónoma diseñada para ejecutarse a pantalla completa en la tablet del chofer (10" horizontal / Landscape) en la cabina del bus.

---

## Características Principales

1. **Diseño Full Viewport Táctil (100vw × 100vh):**
   - Sin marcos decorativos de escritorio. Ocupa el 100% de la pantalla de cualquier tablet Android, iPad o pantalla embebida.
   - Botones táctiles de gran formato (altura mínima 48–60px) para operación segura con un solo toque.

2. **Validación de Pasajes en Tiempo Real:**
   - **Banner compacto superior:** Código de colores normativo:
     - 🟡 **Amarillo:** Medio Pasaje Universitario (`S/. 0.70`).
     - 🟢 **Verde:** Pasaje Adulto General (`S/. 1.50`).
     - ♿ **Amarillo/Pase Libre:** CONADIS (`S/. 0.00`).
     - 🔴 **Rojo:** Saldo Insuficiente / Rechazo (`NO PASA`).
   - **Privacidad del Pasajero:** Se omite el nombre de las personas y se muestra únicamente el medio de cobro (*Aplicativo Móvil, Yape/Plin QR, Validador POS o Pase Libre Carnet*).

3. **Motor de Audio Realista (Web Audio API):**
   - **Tono Verde (880 Hz):** Confirmación agradable de pasaje cobrado.
   - **Tono Rojo (Doble Buzzer 300Hz ➔ 210Hz):** Pitido grave característico de validador de bus cuando un cobro es denegado o no tiene saldo.

4. **Prevención de Reposo (Screen Wake Lock API):**
   - Mantiene la pantalla de la tablet permanentemente encendida mientras el vehículo esté en ruta, evitando que se apague o bloquee.

5. **Aforo en Vivo y Liquidación de Turno:**
   - Contador de capacidad máxima (32 pasajeros) con semáforo de disponibilidad y botones táctiles rápidos `+1` / `-1`.
   - Cierre de turno y liquidación consolidada para transmitir a Central Backoffice.

6. **Sensores Vehiculares y Protocolo de Avería (CU-04 / CU-04.A):**
   - Monitoreo de telemetría CAN-Bus / OBD-II.
   - El botón **"Avería de Unidad"** permanece bloqueado por seguridad y solo se habilita si el propio vehículo reporta una incidencia (puertas abiertas, baja presión de neumáticos o falla de motor).
   - Menú desplegable con opción de **"Pausar en Mapa Público"** para ocultar el bus ante los pasajeros sin alterar el seguimiento de la central.

---

## Cómo Ejecutar Localmente

### Opción 1: Directo en el Navegador
Abre `driver-web/index.html` en Chrome, Edge o Safari.

### Opción 2: Servidor Local para probar desde una Tablet en la misma red Wi-Fi
Desde la terminal en la raíz del proyecto:
```bash
python -m http.server 8080 --directory driver-web
```
Luego en tu tablet conectada a la misma red Wi-Fi ingresa a:
`http://TU_IP_LOCAL:8080` (ejemplo: `http://192.168.1.15:8080`)

---

## Configuración en Nginx (Servidor Cloud)

Para que el servidor en la nube sirva la tablet en la ruta `/chofer` con el mismo usuario y contraseña que el panel de administración:

```nginx
location /chofer {
    alias /home/admin/sem-bus/driver-web;
    index index.html;

    # Misma autenticación que el panel de administración
    auth_basic "Acceso Chofer Cabina • Bus Conectado";
    auth_basic_user_file /etc/nginx/.htpasswd;

    try_files $uri $uri/ /chofer/index.html;
    add_header Cache-Control "no-cache";
}
```
Acceso resultante:
`http://34.61.17.233/chofer` (o tu IP / dominio actual).

