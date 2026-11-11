#!/usr/bin/env python3
"""
BUS CONECTADO • SERVIDOR BACKEND EN RED LOCAL
Diseñado para sincronización directa entre Mac (Admin Web) y iPhone físico (Kitox).
Cero dependencias externas: utiliza exclusivamente la biblioteca estándar de Python 3.
"""

import http.server
import json
import mimetypes
import os
import socket
import sys
import threading
from pathlib import Path
from urllib.parse import parse_qs, urlparse

# Directorios de referencia
BASE_DIR = Path(__file__).resolve().parent.parent
ADMIN_WEB_DIR = BASE_DIR / "admin-web"
PARADEROS_JSON_PATH = ADMIN_WEB_DIR / "paraderos_tacna.json"

PORT = int(os.environ.get("PORT", 8000))
HOST = "0.0.0.0"


def get_local_ip_addresses():
    """Detecta las direcciones IP locales para conectar el iPhone al Mac."""
    ips = set()
    # 1. Dirección del socket saliente
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(0.5)
        s.connect(("8.8.8.8", 80))
        ips.add(s.getsockname()[0])
        s.close()
    except Exception:
        pass

    # 2. Hostname local
    try:
        hostname = socket.gethostname()
        for ip in socket.gethostbyname_ex(hostname)[2]:
            if not ip.startswith("127."):
                ips.add(ip)
    except Exception:
        pass

    # 3. IP conocida del iPhone conectado (USB / Hotspot 172.20.10.x)
    try:
        import subprocess
        out = subprocess.check_output(["ifconfig"], text=True)
        for line in out.splitlines():
            line = line.strip()
            if line.startswith("inet ") and not line.startswith("inet 127."):
                parts = line.split()
                if len(parts) >= 2:
                    ips.add(parts[1])
    except Exception:
        pass

    # Ordenar priorizando 172.20.10.x (iPhone USB/Hotspot) y luego 192.168.x.x
    sorted_ips = sorted(
        list(ips),
        key=lambda ip: (0 if ip.startswith("172.20.10.") else (1 if ip.startswith("192.168.") else 2))
    )
    return sorted_ips or ["127.0.0.1"]


def load_paraderos():
    """Lee el catálogo de paraderos desde paraderos_tacna.json."""
    if PARADEROS_JSON_PATH.exists():
        try:
            with open(PARADEROS_JSON_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"[WARN] Error al leer {PARADEROS_JSON_PATH}: {e}")
    return []


def save_paraderos(stops_data):
    """Guarda el catálogo actualizado de paraderos en paraderos_tacna.json."""
    try:
        with open(PARADEROS_JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(stops_data, f, indent=2, ensure_ascii=False)
        return True
    except Exception as e:
        print(f"[ERROR] Error al guardar {PARADEROS_JSON_PATH}: {e}")
        return False


class BusConectadoRequestHandler(http.server.BaseHTTPRequestHandler):
    """Manejador HTTP REST para Bus Conectado (CORS, Paraderos, Red de Transporte y Web Admin)."""

    def send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, Accept, X-Requested-With")
        self.send_header("Access-Control-Max-Age", "86400")

    def do_OPTIONS(self):
        """Manejo de preflight CORS para clientes Web e iOS."""
        self.send_response(200)
        self.send_cors_headers()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def send_json(self, data, status_code=200):
        try:
            body = json.dumps(data, ensure_ascii=False).encode("utf-8")
            self.send_response(status_code)
            self.send_cors_headers()
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")

        # ── Health Check ──
        if path == "/health" or path == "/api/v1/health":
            stops = load_paraderos()
            return self.send_json({
                "status": "healthy",
                "service": "Bus Conectado Local Backend",
                "version": "1.0.0",
                "stops_count": len(stops),
                "host_ips": get_local_ip_addresses()
            })

        # ── API: Lista de Paraderos Oficiales y Propuestas (34 Paraderos de Tacna) ──
        if path == "/api/v1/transit/stops":
            stops = load_paraderos()
            return self.send_json(stops)

        # ── API: Red de Transporte Completa (CU-07 / AuthViewModel.refreshStateFromBackend) ──
        if path == "/api/v1/transit/network":
            stops_raw = load_paraderos()
            bus_stops = []
            for idx, s in enumerate(stops_raw):
                bus_stops.append({
                    "id": s.get("id"),
                    "route_id": "ruta-14",
                    "name": s.get("name"),
                    "subtitle": s.get("subtitle", ""),
                    "latitude": s.get("latitude"),
                    "longitude": s.get("longitude"),
                    "sequence_order": idx + 1,
                    "direction": "SUR_A_NORTE",
                    "is_key_stop": s.get("isOfficial", True),
                    "approaching_buses": []
                })

            routes = [
                {
                    "id": "ruta-14",
                    "line_number": "14",
                    "name": "Ruta 14 (Cono Sur • Centro • Cono Norte)",
                    "origin_name": "Asoc. Vista Alegre / Viñani",
                    "destination_name": "Ciudad Nueva / Cono Norte",
                    "frequency_minutes": 6,
                    "operating_hours": "05:00 - 22:30",
                    "color_hex": "#2563EB",
                    "stops": bus_stops
                },
                {
                    "id": "ruta-10b",
                    "line_number": "10B",
                    "name": "Ruta 10B (Gregorio Albarracín • Mercado Grau • Leguía)",
                    "origin_name": "Mercado Cenepa",
                    "destination_name": "Cono Norte",
                    "frequency_minutes": 8,
                    "operating_hours": "05:30 - 22:00",
                    "color_hex": "#0D9488",
                    "stops": []
                }
            ]

            return self.send_json({
                "routes": routes,
                "stops": bus_stops,
                "active_buses": []
            })

        # ── API: Saldo de Monedero ──
        if path == "/api/v1/wallet/balance":
            return self.send_json({
                "points": 350,
                "currency": "PTS",
                "pen_equivalent": "3.50 PEN"
            })

        # ── Servir archivos estáticos del Panel Web de Administración (admin-web/) ──
        local_rel = parsed.path.lstrip("/")
        if not local_rel or local_rel == "admin":
            local_rel = "index.html"

        file_path = ADMIN_WEB_DIR / local_rel
        if file_path.is_file():
            mime_type, _ = mimetypes.guess_type(str(file_path))
            mime_type = mime_type or "application/octet-stream"
            try:
                with open(file_path, "rb") as f:
                    content = f.read()
                self.send_response(200)
                self.send_cors_headers()
                self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
                self.send_header("Pragma", "no-cache")
                self.send_header("Expires", "0")
                self.send_header("Content-Type", f"{mime_type}; charset=utf-8" if "text" in mime_type or "javascript" in mime_type or "json" in mime_type else mime_type)
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
                return
            except (BrokenPipeError, ConnectionResetError):
                return
            except Exception as e:
                return self.send_json({"error": f"Error leyendo archivo: {e}"}, status_code=500)

        # 404 No encontrado
        self.send_json({"error": "Endpoint no encontrado", "path": parsed.path}, status_code=404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")

        content_length = int(self.headers.get("Content-Length", 0))
        body_bytes = self.rfile.read(content_length) if content_length > 0 else b"{}"

        try:
            payload = json.loads(body_bytes.decode("utf-8")) if body_bytes else {}
        except Exception:
            payload = {}

        # ── API: Guardar Actualización de Paraderos (Enviado desde admin-web) ──
        if path == "/api/v1/transit/stops" or path == "/api/v1/transit/stops/save-all":
            if isinstance(payload, list) and len(payload) > 0:
                success = save_paraderos(payload)
                if success:
                    print(f"✅ [BACKEND] {len(payload)} paraderos actualizados y guardados en paraderos_tacna.json")
                    return self.send_json({
                        "status": "success",
                        "message": f"{len(payload)} paraderos guardados con éxito",
                        "count": len(payload)
                    })
                else:
                    return self.send_json({"error": "No se pudo escribir en el archivo JSON"}, status_code=500)
            elif isinstance(payload, dict) and "stops" in payload:
                stops_list = payload["stops"]
                save_paraderos(stops_list)
                return self.send_json({
                    "status": "success",
                    "message": f"{len(stops_list)} paraderos guardados con éxito",
                    "count": len(stops_list)
                })
            else:
                return self.send_json({"error": "Payload inválido. Se esperaba lista de paraderos."}, status_code=400)

        # ── API: Autenticación OTP (Simulación Local) ──
        if path == "/api/v1/auth/otp/send":
            phone = payload.get("phone", "+51952000000")
            print(f"📱 [BACKEND] Solicitud OTP para teléfono: {phone}. Código: 123456")
            return self.send_json({
                "status": "sent",
                "phone": phone,
                "message": "Código de verificación enviado. Código de desarrollo: 123456"
            })

        if path == "/api/v1/auth/otp/verify":
            phone = payload.get("phone", "+51952000000")
            code = payload.get("code", "")
            if code == "123456":
                user_id = "user_tacna_" + phone.replace("+", "").replace(" ", "")
                return self.send_json({
                    "access_token": f"jwt_access_{user_id}",
                    "refresh_token": f"jwt_refresh_{user_id}",
                    "user": {
                        "id": user_id,
                        "phone": phone,
                        "display_name": "Usuario Tacna",
                        "email": "usuario@tacna.pe",
                        "is_student": False,
                        "role": "PASSENGER",
                        "profile_icon_name": "person.crop.circle.fill"
                    }
                })
            else:
                return self.send_json({"detail": "Código OTP incorrecto. Utiliza 123456 en entorno local."}, status_code=400)

        # ── API: Recarga de Puntos ──
        if path == "/api/v1/wallet/recharge":
            points = payload.get("amountPoints", 100)
            return self.send_json({
                "status": "success",
                "message": f"Recarga de {points} puntos completada",
                "new_balance": 350 + points
            })

        self.send_json({"error": "Endpoint POST no encontrado", "path": path}, status_code=404)

    def log_message(self, format, *args):
        """Formato limpio de logs de consola protegido contra broken pipes."""
        try:
            sys.stderr.write(f"[{self.log_date_time_string()}] {format % args}\n")
            sys.stderr.flush()
        except Exception:
            pass


def run_server():
    server = http.server.ThreadingHTTPServer((HOST, PORT), BusConectadoRequestHandler)
    ips = get_local_ip_addresses()

    print("═══════════════════════════════════════════════════════════════════════")
    print("   🚌 BUS CONECTADO • SERVIDOR BACKEND EN RED LOCAL (TACNA)")
    print("═══════════════════════════════════════════════════════════════════════")
    print(f"   🟢 Estado: En ejecución en puerto {PORT}")
    print("   📍 Direcciones disponibles para conexión:")
    print(f"      • En esta Mac (Navegador):   http://localhost:{PORT}")
    for ip in ips:
        label = "iPhone (USB / Hotspot)" if ip.startswith("172.20.10.") else "Red Wi-Fi Local"
        print(f"      • Para tu iPhone [{label}]: http://{ip}:{PORT}")
    print("")
    print(f"   🌐 Panel Web Administrador:   http://localhost:{PORT}/")
    print(f"   📡 Endpoint Paraderos:        http://localhost:{PORT}/api/v1/transit/stops")
    print(f"   🔄 Red de Transporte:         http://localhost:{PORT}/api/v1/transit/network")
    print("═══════════════════════════════════════════════════════════════════════")
    print("Presiona Ctrl + C para detener el servidor.\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[INFO] Servidor detenido por el usuario.")
        server.server_close()


if __name__ == "__main__":
    run_server()

