#!/usr/bin/env python3
"""
BUS CONECTADO • SERVIDOR BACKEND EN RED LOCAL
Diseñado para sincronización directa entre Mac (Admin Web) y iPhone físico (Kitox).
Cero dependencias externas: utiliza exclusivamente la biblioteca estándar de Python 3.
"""

import base64
import hashlib
import http.server
import json
import mimetypes
import os
import socket
import struct
import sys
import threading
import time
import uuid
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


PARADEROS_BACKUP_PATH = ADMIN_WEB_DIR / "paraderos_tacna.backup.json"
file_io_lock = threading.Lock()


def load_paraderos():
    """Lee el catálogo de paraderos desde paraderos_tacna.json con recuperación de fallos y respaldo."""
    with file_io_lock:
        if PARADEROS_JSON_PATH.exists():
            try:
                with open(PARADEROS_JSON_PATH, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, list) and len(data) > 0:
                        return data
            except Exception as e:
                print(f"[WARN] Error al leer {PARADEROS_JSON_PATH}: {e}")

        # Intentar cargar desde backup de seguridad si el principal está vacío o dañado
        if PARADEROS_BACKUP_PATH.exists():
            try:
                with open(PARADEROS_BACKUP_PATH, "r", encoding="utf-8") as f:
                    backup_data = json.load(f)
                    if isinstance(backup_data, list) and len(backup_data) > 0:
                        print("[RESTORE] Paraderos restaurados exitosamente desde backup de seguridad.")
                        return backup_data
            except Exception:
                pass
    return []


def save_paraderos(stops_data):
    """Guarda el catálogo actualizado de paraderos de forma atómica y segura con fsync y backup."""
    if not isinstance(stops_data, list) or len(stops_data) == 0:
        print("[WARN] Intento de guardar lista de paraderos vacía o inválida rechazado.")
        return False

    with file_io_lock:
        try:
            # 1. Escribir a archivo temporal
            temp_path = PARADEROS_JSON_PATH.with_suffix(".tmp")
            with open(temp_path, "w", encoding="utf-8") as f:
                json.dump(stops_data, f, indent=2, ensure_ascii=False)
                f.flush()
                os.fsync(f.fileno())

            # 2. Reemplazo atómico POSIX
            os.replace(temp_path, PARADEROS_JSON_PATH)

            # 3. Guardar copia de backup de seguridad
            try:
                import shutil
                shutil.copy2(PARADEROS_JSON_PATH, PARADEROS_BACKUP_PATH)
            except Exception:
                pass

            return True
        except Exception as e:
            print(f"[ERROR] Error al guardar {PARADEROS_JSON_PATH}: {e}")
            return False


# ═══════════════════════════════════════════════════════════════════════
# MOTOR COLABORATIVO EN TIEMPO REAL (WEBSOCKETS RFC 6455)
# ═══════════════════════════════════════════════════════════════════════

def encode_ws_frame(payload_bytes, opcode=1):
    """Codifica un payload de bytes en un frame WebSocket RFC 6455."""
    header = bytearray([0x80 | opcode])
    length = len(payload_bytes)
    if length <= 125:
        header.append(length)
    elif length <= 65535:
        header.append(126)
        header.extend(struct.pack(">H", length))
    else:
        header.append(127)
        header.extend(struct.pack(">Q", length))
    return bytes(header) + payload_bytes


def decode_ws_frame(rfile):
    """Lee y decodifica un frame WebSocket entrante del cliente con soporte de máscaras."""
    try:
        b1_raw = rfile.read(1)
        if not b1_raw:
            return None, None
        b1 = b1_raw[0]
        opcode = b1 & 0x0F

        b2_raw = rfile.read(1)
        if not b2_raw:
            return None, None
        b2 = b2_raw[0]
        masked = (b2 >> 7) & 1
        length = b2 & 0x7F

        if length == 126:
            l_bytes = rfile.read(2)
            if len(l_bytes) < 2: return None, None
            length = struct.unpack(">H", l_bytes)[0]
        elif length == 127:
            l_bytes = rfile.read(8)
            if len(l_bytes) < 8: return None, None
            length = struct.unpack(">Q", l_bytes)[0]

        mask_key = rfile.read(4) if masked else None
        payload = rfile.read(length) if length > 0 else b""

        if masked and mask_key and payload:
            payload = bytes([b ^ mask_key[i % 4] for i, b in enumerate(payload)])

        return opcode, payload
    except Exception:
        return None, None


class CollaborativeHub:
    """Hub centralizado de colaboración en vivo para Administradores de Tacna (Estilo Google Docs)."""
    def __init__(self):
        self.clients = {}  # {client_id: {"handler": handler, "user": user_dict}}
        self.locked_stops = {}  # {stop_id: {"user": user_dict, "timestamp": float}}
        self.lock = threading.Lock()

    def register(self, client_id, handler, user_dict):
        with self.lock:
            self.clients[client_id] = {"handler": handler, "user": user_dict}
        self.broadcast_presence()

    def unregister(self, client_id):
        user_info = None
        with self.lock:
            if client_id in self.clients:
                user_info = self.clients[client_id].get("user")
                del self.clients[client_id]
            if user_info:
                uid = user_info.get("id")
                # Liberar bloqueos de paraderos que tuviera este usuario
                self.locked_stops = {
                    sid: lock for sid, lock in self.locked_stops.items()
                    if lock.get("user", {}).get("id") != uid
                }
        self.broadcast_presence()

    def lock_stop(self, stop_id, user_dict):
        with self.lock:
            self.locked_stops[stop_id] = {"user": user_dict, "timestamp": time.time()}
        self.broadcast({
            "type": "stop_locked",
            "stopId": stop_id,
            "user": user_dict,
            "lockedStops": self.get_locks()
        })

    def unlock_stop(self, stop_id):
        with self.lock:
            if stop_id in self.locked_stops:
                del self.locked_stops[stop_id]
        self.broadcast({
            "type": "stop_unlocked",
            "stopId": stop_id,
            "lockedStops": self.get_locks()
        })

    def get_locks(self):
        return {sid: info["user"] for sid, info in self.locked_stops.items()}

    def get_active_users(self):
        with self.lock:
            return [info["user"] for info in self.clients.values()]

    def broadcast_presence(self):
        users = self.get_active_users()
        locks = self.get_locks()
        self.broadcast({
            "type": "presence_update",
            "activeUsers": users,
            "lockedStops": locks
        })

    def broadcast(self, data_dict, exclude_id=None):
        try:
            msg_bytes = encode_ws_frame(json.dumps(data_dict, ensure_ascii=False).encode("utf-8"))
            with self.lock:
                for cid, client in list(self.clients.items()):
                    if cid == exclude_id:
                        continue
                    try:
                        client["handler"].wfile.write(msg_bytes)
                        client["handler"].wfile.flush()
                    except Exception:
                        pass
        except Exception:
            pass


ws_hub = CollaborativeHub()


class BusConectadoRequestHandler(http.server.BaseHTTPRequestHandler):
    """Manejador HTTP REST para Bus Conectado (CORS, Paraderos, Red de Transporte y Web Admin)."""
    protocol_version = "HTTP/1.1"

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

    def send_json(self, data, status_code=200, cacheable=False):
        try:
            body = json.dumps(data, ensure_ascii=False).encode("utf-8")
            etag = f'"{hashlib.md5(body).hexdigest()}"'

            # Si el cliente ya tiene esta versión exacta en su caché (ETag), responde 304 Not Modified (0 bytes transferidos)
            if cacheable and status_code == 200 and self.headers.get("If-None-Match") == etag:
                self.send_response(304)
                self.send_cors_headers()
                self.send_header("ETag", etag)
                self.send_header("Cache-Control", "public, max-age=60")
                self.end_headers()
                return

            self.send_response(status_code)
            self.send_cors_headers()
            if cacheable:
                self.send_header("ETag", etag)
                self.send_header("Cache-Control", "public, max-age=60")
            else:
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

        # ── Canal WebSocket Colaborativo en Tiempo Real (RFC 6455) ──
        if path == "/ws" or self.headers.get("Upgrade", "").lower() == "websocket":
            return self.handle_websocket()

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
            return self.send_json(stops, cacheable=True)

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
            }, cacheable=True)

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

    def handle_websocket(self):
        """Manejo de WebSocket bidireccional RFC 6455 para colaboración en vivo estilo Google Docs."""
        key = self.headers.get("Sec-WebSocket-Key")
        if not key:
            self.send_error(400, "Sec-WebSocket-Key requerido")
            return

        accept_val = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("utf-8")).digest()).decode("utf-8")
        self.send_response(101, "Switching Protocols")
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept_val)
        self.end_headers()

        # Desactivar timeout de socket para conexión continua
        try:
            self.request.settimeout(None)
        except Exception:
            pass

        client_id = str(uuid.uuid4())[:8]
        current_user = {
            "id": client_id,
            "username": "admin",
            "name": "Admin 1 (Aron)",
            "color": "#38BDF8"
        }
        ws_hub.register(client_id, self, current_user)
        print(f"⚡ [WS] Nuevo administrador conectado: {client_id}")

        try:
            while True:
                opcode, payload = decode_ws_frame(self.rfile)
                if opcode is None or opcode == 8:
                    break
                if opcode == 9:  # Ping
                    self.wfile.write(encode_ws_frame(payload, opcode=10))
                    self.wfile.flush()
                    continue
                if opcode == 1:  # Mensaje de texto JSON
                    try:
                        msg = json.loads(payload.decode("utf-8"))
                        mtype = msg.get("type")

                        if mtype == "join":
                            user_data = msg.get("user", {})
                            current_user.update(user_data)
                            ws_hub.broadcast_presence()

                        elif mtype == "lock_stop":
                            stop_id = msg.get("stopId")
                            ws_hub.lock_stop(stop_id, current_user)

                        elif mtype == "unlock_stop":
                            stop_id = msg.get("stopId")
                            ws_hub.unlock_stop(stop_id)

                        elif mtype == "drag_stop":
                            ws_hub.broadcast({
                                "type": "stop_moving",
                                "stopId": msg.get("stopId"),
                                "lat": msg.get("lat"),
                                "lng": msg.get("lng"),
                                "user": current_user
                            }, exclude_id=client_id)

                        elif mtype == "save_stop":
                            stop_data = msg.get("stop")
                            if stop_data:
                                stop_id = stop_data.get("id")
                                stops = load_paraderos()
                                updated = False
                                for i, s in enumerate(stops):
                                    if s.get("id") == stop_id:
                                        stops[i] = stop_data
                                        updated = True
                                        break
                                if not updated:
                                    stops.append(stop_data)
                                save_paraderos(stops)
                                ws_hub.unlock_stop(stop_id)
                                ws_hub.broadcast({
                                    "type": "stop_saved",
                                    "stop": stop_data,
                                    "user": current_user,
                                    "allStopsCount": len(stops)
                                })

                        elif mtype == "delete_stop":
                            stop_id = msg.get("stopId")
                            stops = load_paraderos()
                            stops = [s for s in stops if s.get("id") != stop_id]
                            save_paraderos(stops)
                            ws_hub.unlock_stop(stop_id)
                            ws_hub.broadcast({
                                "type": "stop_deleted",
                                "stopId": stop_id,
                                "user": current_user,
                                "allStopsCount": len(stops)
                            })

                        elif mtype == "cursor_move":
                            ws_hub.broadcast({
                                "type": "cursor_moved",
                                "lat": msg.get("lat"),
                                "lng": msg.get("lng"),
                                "user": current_user
                            }, exclude_id=client_id)

                    except Exception as e:
                        pass
        except Exception:
            pass
        finally:
            print(f"⚡ [WS] Administrador desconectado: {client_id}")
            ws_hub.unregister(client_id)

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
                    ws_hub.broadcast({"type": "stops_reloaded", "count": len(payload), "stops": payload})
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
                ws_hub.broadcast({"type": "stops_reloaded", "count": len(stops_list), "stops": stops_list})
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

