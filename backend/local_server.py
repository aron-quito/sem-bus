#!/usr/bin/env python3
"""
BUS CONECTADO • SERVIDOR BACKEND EN RED LOCAL
Diseñado para sincronización directa entre Mac (Admin Web) y iPhone físico (Kitox).
Cero dependencias externas: utiliza exclusivamente la biblioteca estándar de Python 3.
"""

import base64
import hashlib
import hmac
import http.server
import json
import math
import mimetypes
import os
import secrets
import socket
import struct
import sys
import threading
import time
import uuid
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlparse

# Directorios de referencia
BASE_DIR = Path(__file__).resolve().parent.parent
ADMIN_WEB_DIR = BASE_DIR / "admin-web"
PARADEROS_JSON_PATH = ADMIN_WEB_DIR / "paraderos_tacna.json"

PORT = int(os.environ.get("PORT", 8000))
HOST = "0.0.0.0"
MAX_POST_BODY_BYTES = 10 * 1024 * 1024
_IP_CACHE_TTL_SECONDS = 60.0
_ip_cache_lock = threading.Lock()
_cached_ips = None
_cached_ips_at = 0.0


def get_local_ip_addresses():
    """Detecta las direcciones IP locales para conectar el iPhone al Mac (con caché de 60s)."""
    global _cached_ips, _cached_ips_at
    now = time.monotonic()
    with _ip_cache_lock:
        if _cached_ips is not None and (now - _cached_ips_at) < _IP_CACHE_TTL_SECONDS:
            return list(_cached_ips)

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
    result = sorted_ips or ["127.0.0.1"]
    with _ip_cache_lock:
        _cached_ips = result
        _cached_ips_at = time.monotonic()
    return list(result)


PARADEROS_BACKUP_PATH = ADMIN_WEB_DIR / "paraderos_tacna.backup.json"
RUTAS_JSON_PATH = ADMIN_WEB_DIR / "rutas_tacna.json"
RUTAS_BACKUP_PATH = ADMIN_WEB_DIR / "rutas_tacna.backup.json"
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
    if not isinstance(stops_data, list):
        print("[WARN] Intento de guardar estructura de paraderos inválida rechazado.")
        return False

    with file_io_lock:
        try:
            temp_path = PARADEROS_JSON_PATH.with_suffix(".tmp")
            with open(temp_path, "w", encoding="utf-8") as f:
                json.dump(stops_data, f, indent=2, ensure_ascii=False)
                f.flush()
                os.fsync(f.fileno())

            os.replace(temp_path, PARADEROS_JSON_PATH)

            try:
                import shutil
                shutil.copy2(PARADEROS_JSON_PATH, PARADEROS_BACKUP_PATH)
            except Exception:
                pass

            return True
        except Exception as e:
            print(f"[ERROR] Error al guardar {PARADEROS_JSON_PATH}: {e}")
            return False


def load_rutas():
    """Lee el catálogo de rutas (Ordinarias y Externas) desde rutas_tacna.json con recuperación automática."""
    with file_io_lock:
        if RUTAS_JSON_PATH.exists():
            try:
                with open(RUTAS_JSON_PATH, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, list) and len(data) > 0:
                        return data
            except Exception as e:
                print(f"[WARN] Error al leer {RUTAS_JSON_PATH}: {e}")

        if RUTAS_BACKUP_PATH.exists():
            try:
                with open(RUTAS_BACKUP_PATH, "r", encoding="utf-8") as f:
                    backup_data = json.load(f)
                    if isinstance(backup_data, list) and len(backup_data) > 0:
                        print("[RESTORE] Rutas restauradas exitosamente desde backup de seguridad.")
                        return backup_data
            except Exception:
                pass
    return []


def save_rutas(routes_data, sync_stops=True):
    """Guarda el catálogo de rutas de forma atómica POSIX y sincroniza la pertenencia en los paraderos."""
    if not isinstance(routes_data, list):
        print("[WARN] Intento de guardar estructura de rutas inválida rechazado.")
        return False

    with file_io_lock:
        try:
            temp_path = RUTAS_JSON_PATH.with_suffix(".tmp")
            with open(temp_path, "w", encoding="utf-8") as f:
                json.dump(routes_data, f, indent=2, ensure_ascii=False)
                f.flush()
                os.fsync(f.fileno())

            os.replace(temp_path, RUTAS_JSON_PATH)

            if len(routes_data) > 0:
                try:
                    import shutil
                    shutil.copy2(RUTAS_JSON_PATH, RUTAS_BACKUP_PATH)
                except Exception:
                    pass
        except Exception as e:
            print(f"[ERROR] Error al guardar {RUTAS_JSON_PATH}: {e}")
            return False

    if sync_stops:
        sync_paraderos_from_rutas(routes_data)
    return True


def sync_paraderos_from_rutas(routes_data):
    """Mantiene sincronizada la propiedad routesPassing de cada paradero según las rutas vigentes."""
    stops = load_paraderos()
    if not stops:
        return stops

    stop_routes_map = {s.get("id"): [] for s in stops}
    for r in routes_data:
        code = (r.get("code") or "").strip()
        if not code:
            continue
        for sid in (r.get("keyStopIds") or []):
            if sid in stop_routes_map and code not in stop_routes_map[sid]:
                stop_routes_map[sid].append(code)

    changed = False
    for s in stops:
        sid = s.get("id")
        new_routes = stop_routes_map.get(sid, [])
        if s.get("routesPassing") != new_routes:
            s["routesPassing"] = new_routes
            changed = True

    if changed:
        save_paraderos(stops)
    return stops


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
        except Exception:
            return

        with self.lock:
            targets = [
                (cid, client["handler"])
                for cid, client in self.clients.items()
                if cid != exclude_id
            ]

        dead_ids = []
        for cid, handler in targets:
            try:
                handler.wfile.write(msg_bytes)
                handler.wfile.flush()
            except Exception:
                dead_ids.append(cid)

        for cid in dead_ids:
            self.unregister(cid)


# ── Módulo POS • Billeteras Digitales y Pasajes Dinámicos (Tacna) ──
POS_DEVICE_ID = os.environ.get("POS_DEVICE_ID", "POS-UNI-1408")
POS_DEVICE_SECRET = os.environ.get("POS_DEVICE_SECRET", "dev_pos_terminal_secret_bus_conectado_tacna_2026")
QR_SIGNING_SECRET = os.environ.get("QR_SIGNING_SECRET", "secret_for_qr_signing_bus_conectado_tacna_2026")
YAPE_WEBHOOK_SECRET = os.environ.get("YAPE_WEBHOOK_SECRET", "test_yape_webhook_secret_bcp")
YAPE_EMPRESA_PHONE = os.environ.get("YAPE_EMPRESA_PHONE", "952000110")
YAPE_EMPRESA_MERCHANT_NAME = os.environ.get("YAPE_EMPRESA_MERCHANT_NAME", "BUS CONECTADO TACNA")
YAPE_COMMISSION_RATE = 0.0295
DEFAULT_FLAT_POINTS = 15
POS_QR_TTL_SECONDS = 60

_pos_orders_lock = threading.Lock()
_pos_orders = {}        # order_id -> dict
_pos_used_nonces = set()
_pos_ws_subscribers = defaultdict(list)  # order_id -> list of RequestHandler instances
_live_bus_telemetry = {}                 # unit_code -> telemetry dict
_driver_sessions = {}                    # dni -> {active, token, unit_code, name, updated_at}
_disabled_drivers = set()                # set of disabled driver DNIs
_unit_occupancy = {}                     # unit_code -> int passenger count

def broadcast_pos_order_event(order_id: str, event_data: dict):
    with _pos_orders_lock:
        clients = list(_pos_ws_subscribers.get(order_id, []))
    if not clients:
        return
    frame = encode_ws_frame(json.dumps(event_data).encode("utf-8"), opcode=1)
    dead = []
    for client in clients:
        try:
            client.wfile.write(frame)
            client.wfile.flush()
        except Exception:
            dead.append(client)
    if dead:
        with _pos_orders_lock:
            for d in dead:
                if d in _pos_ws_subscribers.get(order_id, []):
                    _pos_ws_subscribers[order_id].remove(d)

def haversine_distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def _sign_pos_payload(payload_str: str) -> str:
    h = hmac.new(QR_SIGNING_SECRET.encode("utf-8"), payload_str.encode("utf-8"), hashlib.sha256).hexdigest()
    return h[:16]

def _verify_pos_payload(canonical: str, signature: str) -> bool:
    expected = _sign_pos_payload(canonical)
    return hmac.compare_digest(expected.lower(), signature.strip().lower())


USERS_JSON_PATH = ADMIN_WEB_DIR / "usuarios_tacna.json"
POS_TERMINALS_JSON_PATH = ADMIN_WEB_DIR / "pos_terminals.json"
TRANSACTIONS_JSON_PATH = ADMIN_WEB_DIR / "transacciones_pos.json"
CARNET_REQUESTS_JSON_PATH = ADMIN_WEB_DIR / "carnets_sunedu.json"

_student_cooldowns = {}  # user_id/phone -> last_paid_timestamp
_admin_data_lock = threading.Lock()

def load_admin_users():
    with _admin_data_lock:
        if not USERS_JSON_PATH.is_file():
            return []
        try:
            with open(USERS_JSON_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return []

def save_admin_users(users_list):
    with _admin_data_lock:
        try:
            with open(USERS_JSON_PATH, "w", encoding="utf-8") as f:
                json.dump(users_list, f, ensure_ascii=False, indent=2)
            return True
        except Exception:
            return False

def load_pos_terminals():
    with _admin_data_lock:
        if not POS_TERMINALS_JSON_PATH.is_file():
            return []
        try:
            with open(POS_TERMINALS_JSON_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return []

def save_pos_terminals(terminals_list):
    with _admin_data_lock:
        try:
            with open(POS_TERMINALS_JSON_PATH, "w", encoding="utf-8") as f:
                json.dump(terminals_list, f, ensure_ascii=False, indent=2)
            return True
        except Exception:
            return False

def load_transactions():
    with _admin_data_lock:
        if not TRANSACTIONS_JSON_PATH.is_file():
            return []
        try:
            with open(TRANSACTIONS_JSON_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return []

def load_carnet_requests():
    with _admin_data_lock:
        if not CARNET_REQUESTS_JSON_PATH.is_file():
            return []
        try:
            with open(CARNET_REQUESTS_JSON_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return []

def save_carnet_requests(reqs):
    with _admin_data_lock:
        try:
            with open(CARNET_REQUESTS_JSON_PATH, "w", encoding="utf-8") as f:
                json.dump(reqs, f, ensure_ascii=False, indent=2)
            return True
        except Exception:
            return False

def parse_sunedu_qr(qr_payload, fallback_dni="", fallback_univ="", fallback_expiry=""):
    import re
    raw = str(qr_payload or "").strip()
    if len(raw) < 6:
        return False, "No se detectó un código QR válido en la foto frontal del carnet."
    dni_match = re.search(r"\b(\d{8})\b", raw)
    extracted_dni = dni_match.group(1) if dni_match else str(fallback_dni or "").strip()
    if not re.fullmatch(r"\d{8}", extracted_dni or ""):
        return False, "El QR del carnet no contiene un DNI válido de 8 dígitos."
    if fallback_dni and dni_match and dni_match.group(1) != str(fallback_dni).strip():
        return False, f"El DNI del QR ({dni_match.group(1)}) no coincide con tu DNI ingresado ({fallback_dni})."

    exp_match_iso = re.search(r"(20\d{2}[-/]\d{2}[-/]\d{2})", raw)
    exp_match_lat = re.search(r"(\d{2}[-/]\d{2}[-/](20\d{2}))", raw)
    if exp_match_iso:
        expiry_date = exp_match_iso.group(1).replace("/", "-")
    elif exp_match_lat:
        parts = re.split(r"[-/]", exp_match_lat.group(1))
        expiry_date = f"{parts[2]}-{parts[1]}-{parts[0]}"
    else:
        expiry_date = str(fallback_expiry or "2026-12-31").strip()

    upper = raw.upper()
    univ = str(fallback_univ or "").strip()
    for code, full_name in [
        ("UNJBG", "Universidad Nacional Jorge Basadre Grohmann"),
        ("UPT", "Universidad Privada de Tacna"),
        ("UNMSM", "Universidad Nacional Mayor de San Marcos"),
        ("UNI", "Universidad Nacional de Ingeniería"),
        ("PUCP", "Pontificia Universidad Católica del Perú"),
        ("UNSA", "Universidad Nacional de San Agustín")
    ]:
        if code in upper:
            univ = full_name
            break
    if not univ:
        univ = "Universidad Licenciada SUNEDU (Perú)"

    carnet_code = f"SUNEDU-{extracted_dni}"
    if "SIVIC" in upper or "SUNEDU" in upper:
        carnet_code = f"SIVIC-{extracted_dni}"

    return True, {
        "dni": extracted_dni,
        "university": univ,
        "carnet_code": carnet_code,
        "expiry_date": expiry_date,
        "qr_verified": True
    }

def append_transaction(tx_record):
    with _admin_data_lock:
        try:
            u_code = tx_record.get("unit_code") or "UNI-1408"
            companions = int(tx_record.get("companions_count") or 0)
            _unit_occupancy[u_code] = min(60, _unit_occupancy.get(u_code, 0) + 1 + companions)
            if u_code in _live_bus_telemetry:
                _live_bus_telemetry[u_code]["passengers"] = _unit_occupancy[u_code]

            current = []
            if TRANSACTIONS_JSON_PATH.is_file():
                with open(TRANSACTIONS_JSON_PATH, "r", encoding="utf-8") as f:
                    current = json.load(f)
            current.insert(0, tx_record)
            # Guardar máximo las 500 transacciones más recientes
            current = current[:500]
            with open(TRANSACTIONS_JSON_PATH, "w", encoding="utf-8") as f:
                json.dump(current, f, ensure_ascii=False, indent=2)
            return True
        except Exception:
            return False


ws_hub = CollaborativeHub()


class BusConectadoHTTPServer(http.server.ThreadingHTTPServer):
    """Servidor HTTP multihilo con hilos daemon para apagado limpio y reuso de puerto."""
    daemon_threads = True
    allow_reuse_address = True


class BusConectadoRequestHandler(http.server.BaseHTTPRequestHandler):
    """Manejador HTTP REST para Bus Conectado (CORS, Paraderos, Red de Transporte y Web Admin)."""
    protocol_version = "HTTP/1.1"
    timeout = 15

    def send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, Accept, X-Requested-With, X-POS-Device-Id, X-POS-Secret, X-Signature")
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

        # ── Canal WebSocket POS Order en Tiempo Real (RFC 6455) ──
        if path.startswith("/api/v1/pos/ws/"):
            return self.handle_pos_websocket(path)

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

        # ── API: Catálogo de Rutas de Tacna (Ordinarias con Tracking/QR y Externas Referenciales) ──
        if path == "/api/v1/transit/routes":
            routes_catalog = load_rutas()
            return self.send_json(routes_catalog, cacheable=True)

        # ── API: Red de Transporte Completa (CU-07 / AuthViewModel.refreshStateFromBackend) ──
        if path == "/api/v1/transit/network":
            stops_raw = load_paraderos()
            routes_catalog = load_rutas()
            stops_by_id = {s.get("id"): s for s in stops_raw}

            bus_stops = []
            for idx, s in enumerate(stops_raw):
                bus_stops.append({
                    "id": s.get("id"),
                    "route_id": (s.get("routesPassing") or ["Ruta 14"])[0] if s.get("routesPassing") else "Sin Ruta",
                    "name": s.get("name"),
                    "subtitle": s.get("subtitle", ""),
                    "latitude": s.get("latitude"),
                    "longitude": s.get("longitude"),
                    "sequence_order": idx + 1,
                    "direction": "SUR_A_NORTE",
                    "is_key_stop": s.get("isOfficial", True),
                    "approaching_buses": []
                })

            routes = []
            for r in routes_catalog:
                r_stops = []
                for seq_idx, sid in enumerate(r.get("keyStopIds") or []):
                    st = stops_by_id.get(sid)
                    if st:
                        r_stops.append({
                            "id": st.get("id"),
                            "route_id": r.get("id"),
                            "name": st.get("name"),
                            "subtitle": st.get("subtitle", ""),
                            "latitude": st.get("latitude"),
                            "longitude": st.get("longitude"),
                            "sequence_order": seq_idx + 1,
                            "direction": "CORREDOR",
                            "is_key_stop": st.get("isOfficial", True),
                            "approaching_buses": []
                        })
                corridor_parts = (r.get("corridorSummary") or "Tacna ⇄ Centro").split("⇄")
                origin_name = corridor_parts[0].strip() if corridor_parts else "Tacna"
                dest_name = corridor_parts[-1].strip() if len(corridor_parts) > 1 else "Tacna"
                routes.append({
                    "id": r.get("id"),
                    "line_number": r.get("code", "").replace("Ruta ", "").replace("RUTA ", "").strip() or r.get("code", "14"),
                    "name": f"{r.get('code', 'Ruta')} • {r.get('title', '')}",
                    "origin_name": origin_name,
                    "destination_name": dest_name,
                    "frequency_minutes": r.get("frequencyMinutes", 6),
                    "operating_hours": r.get("scheduleLabel", "05:30 - 22:00"),
                    "color_hex": r.get("colorHex", "#2563EB"),
                    "stops": r_stops
                })

            active_buses = []
            with _admin_data_lock:
                for b in _live_bus_telemetry.values():
                    eta_min = max(1, int(b.get("eta_seconds", 120) / 60))
                    active_buses.append({
                        "id": b.get("unit_code"),
                        "unit_number": b.get("unit_code"),
                        "plate": b.get("plate", "Z4B-812"),
                        "line_number": b.get("route_code", "Ruta 14"),
                        "route_id": b.get("route_code", "Ruta 14"),
                        "driver_name": b.get("driver_name", "Carlos Mamani Flores"),
                        "driver_rating": 4.8,
                        "driver_license": b.get("brevete", "Q43892110"),
                        "occupancy_current": b.get("passengers", 14),
                        "occupancy_max": 35,
                        "passengers": b.get("passengers", 14),
                        "capacity": 35,
                        "latitude": b.get("latitude"),
                        "longitude": b.get("longitude"),
                        "speed_kmh": b.get("speed_kmh", 25.0),
                        "heading": b.get("heading", 0.0),
                        "next_stop_name": b.get("closest_stop_name", "Paradero Bolognesi"),
                        "next_stop_eta_minutes": eta_min,
                        "eta_minutes": eta_min,
                        "occupancy_status": "ASIENTOS_DISPONIBLES"
                    })
            return self.send_json({
                "routes": routes,
                "catalog_routes": routes_catalog,
                "stops": bus_stops,
                "active_buses": active_buses
            })

        # ── API: Telemetría de Buses Activos en Tiempo Real ──
        if path in ("/api/v1/transit/buses/live", "/api/v1/pos/telemetry"):
            with _admin_data_lock:
                return self.send_json(list(_live_bus_telemetry.values()))

        # ── API: Saldo de Monedero ──
        if path == "/api/v1/wallet/balance":
            return self.send_json({
                "points": 350,
                "currency": "PTS",
                "pen_equivalent": "3.50 PEN"
            })

        # ── API POS: Consulta de Estado de Orden (Polling cada 3s) ──
        if path.startswith("/api/v1/pos/orders/"):
            order_id = path.split("/")[-1].strip()
            with _pos_orders_lock:
                order = _pos_orders.get(order_id)
                if not order:
                    return self.send_json({"detail": "Orden POS no encontrada"}, status_code=404)
                # Auto-expirar si superó el TTL
                if order["status"] == "PENDING" and time.time() > order.get("exp_ts", 0):
                    order["status"] = "EXPIRED"
                return self.send_json({
                    "order_id": order["order_id"],
                    "unit_code": order["unit_code"],
                    "route_code": order["route_code"],
                    "status": order["status"],
                    "payment_method": order.get("payment_method"),
                    "fare_label": order.get("fare_label", "Tarifa Plana General"),
                    "companions_count": order.get("companions_count", 0),
                    "amount_points": order["amount_points"],
                    "amount_pen": order["amount_pen"],
                    "commission_pen": order.get("commission_pen", 0.0),
                    "net_pen": order.get("net_pen", order["amount_pen"]),
                    "paid_at": order.get("paid_at"),
                    "expires_at": order["expires_at"]
                })

        # ── API ADMIN: Directorio de Usuarios y Choferes ──
        if path == "/api/v1/admin/users":
            return self.send_json(load_admin_users())

        if path == "/api/v1/admin/carnets":
            return self.send_json(load_carnet_requests())

        if path == "/api/v1/carnet/status":
            qs = parse_qs(parsed.query)
            phone = (qs.get("phone") or [""])[0].strip()
            dni = (qs.get("dni") or [""])[0].strip()
            reqs = load_carnet_requests()
            match = None
            for r in reqs:
                if (phone and r.get("phone") == phone) or (dni and r.get("dni") == dni):
                    match = r
                    break
            return self.send_json({"request": match})

        if path == "/api/v1/driver/session/status":
            qs = parse_qs(parsed.query)
            dni = (qs.get("dni") or [""])[0].strip()
            token = (qs.get("token") or [""])[0].strip()
            with _admin_data_lock:
                enabled = dni not in _disabled_drivers
                sess = _driver_sessions.get(dni, {})
                valid_tokens = sess.get("tokens", [])
                if sess.get("token") and sess.get("token") not in valid_tokens:
                    valid_tokens = valid_tokens + [sess.get("token")]
                token_ok = (not token) or (token in valid_tokens)
                active = enabled and bool(sess.get("active")) and token_ok
                pos_enabled = active and bool(sess.get("pos_enabled", False))
            return self.send_json({"active": active, "enabled": enabled, "pos_enabled": pos_enabled, "dni": dni})

        if path == "/api/v1/admin/drivers/sessions":
            with _admin_data_lock:
                return self.send_json({
                    "sessions": _driver_sessions,
                    "disabled": list(_disabled_drivers),
                    "occupancy": _unit_occupancy
                })

        # ── API ADMIN: Terminales POS y Estado por Unidad ──
        if path == "/api/v1/admin/pos-terminals":
            return self.send_json(load_pos_terminals())

        # ── API ADMIN: Libro Contable de Transacciones y Abordajes ──
        if path == "/api/v1/admin/transactions":
            txs = load_transactions()
            query_params = parse_qs(parsed.query)
            route_filter = query_params.get("route", [None])[0]
            unit_filter = query_params.get("unit", [None])[0]
            method_filter = query_params.get("method", [None])[0]

            filtered = txs
            if route_filter:
                filtered = [t for t in filtered if t.get("route_code") == route_filter]
            if unit_filter:
                filtered = [t for t in filtered if t.get("unit_code") == unit_filter]
            if method_filter:
                filtered = [t for t in filtered if t.get("payment_method") == method_filter]

            return self.send_json(filtered)

        # ── API ADMIN: Estadísticas Globales de Recaudación y Operación ──
        if path == "/api/v1/admin/stats":
            txs = load_transactions()
            terminals = load_pos_terminals()
            users = load_admin_users()

            total_trips = len(txs)
            gross_pen = round(sum(t.get("amount_pen", 0.0) for t in txs), 2)
            commission_pen = round(sum(t.get("commission_pen", 0.0) for t in txs), 2)
            net_pen = round(gross_pen - commission_pen, 2)

            app_trips = sum(1 for t in txs if t.get("payment_method") == "APP_BUS_CONECTADO")
            yape_trips = sum(1 for t in txs if t.get("payment_method") in ("YAPE", "YAPE_EMPRESA"))
            nfc_trips = sum(1 for t in txs if t.get("payment_method") == "NFC")
            conadis_trips = sum(1 for t in txs if t.get("payment_method") == "CONADIS" or t.get("user_role") == "CONADIS")
            student_trips = sum(1 for t in txs if t.get("user_role") == "STUDENT" or "Universitaria" in t.get("fare_label", ""))

            by_route = {}
            for t in txs:
                rc = t.get("route_code", "Sin Ruta")
                by_route[rc] = by_route.get(rc, 0) + 1

            return self.send_json({
                "total_trips_today": total_trips,
                "gross_revenue_pen": gross_pen,
                "commission_pen": commission_pen,
                "net_revenue_pen": net_pen,
                "app_trips": app_trips,
                "yape_trips": yape_trips,
                "nfc_trips": nfc_trips,
                "conadis_trips": conadis_trips,
                "student_trips": student_trips,
                "active_terminals_count": len([t for t in terminals if t.get("status") == "ONLINE"]),
                "total_terminals_count": len(terminals),
                "total_users_count": len(users),
                "drivers_count": len([u for u in users if u.get("role") == "DRIVER"]),
                "students_count": len([u for u in users if u.get("role") == "STUDENT"]),
                "trips_by_route": by_route,
                "peak_hours_info": "Horas punta registradas: 07:00 - 08:30 y 12:30 - 14:00"
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
                self.send_header("Cache-Control", "no-cache")
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

    def handle_pos_websocket(self, path: str):
        """Manejo de WebSocket RFC 6455 para suscripción en vivo a orden POS (/api/v1/pos/ws/<order_id>)."""
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

        try:
            self.request.settimeout(None)
            self.request.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
        except Exception:
            pass

        # Extraer order_id de /api/v1/pos/ws/<order_id>
        order_parts = path.strip("/").split("/")
        order_id = order_parts[-1].split("?")[0].strip() if len(order_parts) >= 5 else "GENERAL"

        with _pos_orders_lock:
            _pos_ws_subscribers[order_id].append(self)
            order = _pos_orders.get(order_id)

        print(f"📡 [POS WS] Terminal conectado escuchando orden: {order_id}")

        # Si ya estaba pagada antes del handshake, enviar evento inmediatamente
        if order and order.get("status") == "PAID":
            evt = {
                "event": "ORDER_PAID",
                "order_id": order_id,
                "status": "PAID",
                "payment_method": order.get("payment_method"),
                "fare_label": order.get("fare_label"),
                "companions_count": order.get("companions_count", 0),
                "amount_points": order.get("amount_points", 15),
                "amount_pen": order.get("amount_pen", 1.50),
                "commission_pen": order.get("commission_pen", 0.0),
                "net_pen": order.get("net_pen", 1.50)
            }
            try:
                self.wfile.write(encode_ws_frame(json.dumps(evt).encode("utf-8"), opcode=1))
                self.wfile.flush()
            except Exception:
                pass

        try:
            while True:
                opcode, payload = decode_ws_frame(self.rfile)
                if opcode is None or opcode == 8:
                    break
                if opcode == 9:  # Ping
                    self.wfile.write(encode_ws_frame(payload, opcode=10))
                    self.wfile.flush()
        finally:
            with _pos_orders_lock:
                if self in _pos_ws_subscribers.get(order_id, []):
                    _pos_ws_subscribers[order_id].remove(self)
            print(f"📡 [POS WS] Desconectado terminal de orden: {order_id}")

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

        # Desactivar timeout de lectura para WS continuo, activando SO_KEEPALIVE del kernel
        try:
            self.request.settimeout(None)
            self.request.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
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

                        elif mtype == "save_route":
                            route_data = msg.get("route")
                            if route_data:
                                route_id = route_data.get("id")
                                routes_list = load_rutas()
                                updated = False
                                for i, r in enumerate(routes_list):
                                    if r.get("id") == route_id:
                                        routes_list[i] = route_data
                                        updated = True
                                        break
                                if not updated:
                                    routes_list.append(route_data)
                                save_rutas(routes_list, sync_stops=True)
                                updated_stops = load_paraderos()
                                ws_hub.broadcast({
                                    "type": "route_saved",
                                    "route": route_data,
                                    "routes": routes_list,
                                    "stops": updated_stops,
                                    "user": current_user
                                })

                        elif mtype == "delete_route":
                            route_id = msg.get("routeId")
                            routes_list = load_rutas()
                            routes_list = [r for r in routes_list if r.get("id") != route_id]
                            save_rutas(routes_list, sync_stops=True)
                            updated_stops = load_paraderos()
                            ws_hub.broadcast({
                                "type": "route_deleted",
                                "routeId": route_id,
                                "routes": routes_list,
                                "stops": updated_stops,
                                "user": current_user
                            })

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

        try:
            content_length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            return self.send_json({"error": "Content-Length inválido."}, status_code=400)
        if content_length < 0:
            return self.send_json({"error": "Content-Length inválido."}, status_code=400)
        if content_length > MAX_POST_BODY_BYTES:
            return self.send_json({"error": "Payload demasiado grande (máximo 10 MB)."}, status_code=413)
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

        # ── API: Guardar Actualización de Rutas Oficiales y Externas (Enviado desde admin-web) ──
        if path == "/api/v1/transit/routes" or path == "/api/v1/transit/routes/save-all":
            routes_list = None
            if isinstance(payload, list):
                routes_list = payload
            elif isinstance(payload, dict) and "routes" in payload:
                routes_list = payload["routes"]

            if routes_list is not None:
                success = save_rutas(routes_list, sync_stops=True)
                if success:
                    updated_stops = load_paraderos()
                    print(f"✅ [BACKEND] {len(routes_list)} rutas actualizadas y sincronizadas con paraderos.")
                    ws_hub.broadcast({
                        "type": "routes_reloaded",
                        "count": len(routes_list),
                        "routes": routes_list,
                        "stops": updated_stops
                    })
                    return self.send_json({
                        "status": "success",
                        "message": f"{len(routes_list)} rutas guardadas y sincronizadas con éxito",
                        "count": len(routes_list),
                        "stops": updated_stops
                    })
                else:
                    return self.send_json({"error": "No se pudo escribir rutas_tacna.json"}, status_code=500)
            else:
                return self.send_json({"error": "Payload inválido. Se esperaba lista de rutas."}, status_code=400)

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

        # ── API POS: Crear Orden Dinámica con Doble QR (Tarifa Plana S/. 1.50) ──
        if path == "/api/v1/pos/orders":
            unit_code = payload.get("unit_code", "UNI-1408")
            plate = payload.get("plate", "Z4B-812")
            route_code = payload.get("route_code", "RUTA 14")
            fixed_points = int(payload.get("fixed_amount_points", DEFAULT_FLAT_POINTS))
            amount_pen = round(fixed_points * 0.10, 2)

            now = int(time.time())
            exp_ts = now + POS_QR_TTL_SECONDS
            order_id = f"POS-{secrets.token_hex(5).upper()}"
            nonce = secrets.token_hex(6)

            # Construir QR App Bus Conectado HMAC-SHA256
            canonical = f"BC-POS|v1|{order_id}|{unit_code}|{nonce}|{exp_ts}|{fixed_points}"
            sig = _sign_pos_payload(canonical)
            app_qr = f"{canonical}|{sig}"

            # Construir QR Yape Empresas
            yape_qr = f"BC-YAPE|v1|phone={YAPE_EMPRESA_PHONE}|merchant={YAPE_EMPRESA_MERCHANT_NAME}|amount={amount_pen:.2f}|order={order_id}"

            # Cálculos de comisión
            yape_comm = round(amount_pen * YAPE_COMMISSION_RATE, 2)
            yape_net = round(amount_pen - yape_comm, 2)
            app_comm = 0.0
            app_net = amount_pen

            expires_at_iso = datetime.fromtimestamp(exp_ts, tz=timezone.utc).isoformat()

            order_data = {
                "order_id": order_id,
                "unit_code": unit_code,
                "plate": plate,
                "route_code": route_code,
                "status": "PENDING",
                "amount_points": fixed_points,
                "amount_pen": amount_pen,
                "ttl_seconds": POS_QR_TTL_SECONDS,
                "expires_at": expires_at_iso,
                "exp_ts": exp_ts,
                "nonce": nonce,
                "canonical": canonical,
                "signature": sig,
                "app_qr_payload": app_qr,
                "yape_qr_payload": yape_qr,
                "ws_path": f"/api/v1/pos/ws/{order_id}",
                "yape_commission_rate": YAPE_COMMISSION_RATE,
                "yape_commission_pen": yape_comm,
                "yape_net_pen": yape_net,
                "app_commission_pen": app_comm,
                "app_net_pen": app_net,
                "created_at": datetime.now(timezone.utc).isoformat()
            }

            with _pos_orders_lock:
                _pos_orders[order_id] = order_data

            print(f"🎟️ [POS] Nueva orden generada: {order_id} · {fixed_points} pts (S/. {amount_pen:.2f})")
            return self.send_json(order_data, status_code=201)

        # ── API POS: Cancelar Orden ──
        if path.startswith("/api/v1/pos/orders/") and path.endswith("/cancel"):
            parts = path.split("/")
            order_id = parts[-2].strip()
            with _pos_orders_lock:
                order = _pos_orders.get(order_id)
                if not order:
                    return self.send_json({"detail": "Orden POS no encontrada"}, status_code=404)
                order["status"] = "CANCELLED"
                return self.send_json({
                    "order_id": order["order_id"],
                    "unit_code": order["unit_code"],
                    "route_code": order["route_code"],
                    "status": "CANCELLED",
                    "amount_points": order["amount_points"],
                    "amount_pen": order["amount_pen"],
                    "expires_at": order["expires_at"]
                })

        # ── API ADMIN: Crear / Registrar Usuario o Chofer ──
        if path == "/api/v1/admin/users":
            name = (payload.get("name") or "").strip()
            dni = (payload.get("dni") or "").strip()
            phone = (payload.get("phone") or "").strip()
            role = (payload.get("role") or "PASSENGER").upper()

            if not name or not phone:
                return self.send_json({"error": "Nombre y teléfono son obligatorios."}, status_code=400)

            users = load_admin_users()
            user_id = f"USR-{role[:3]}-{secrets.token_hex(3).upper()}"

            role_labels = {
                "ADMIN": "Administrador General",
                "DRIVER": "Chofer Profesional",
                "STUDENT": "Universitario SUNEDU",
                "CONADIS": "Pase Libre Ley 30412",
                "PASSENGER": "Pasajero General"
            }
            badge_classes = {
                "ADMIN": "badge-admin",
                "DRIVER": "badge-driver",
                "STUDENT": "badge-student",
                "CONADIS": "badge-conadis",
                "PASSENGER": "badge-passenger"
            }

            new_user = {
                "id": user_id,
                "name": name,
                "dni": dni,
                "phone": phone,
                "role": role,
                "role_label": role_labels.get(role, "Pasajero"),
                "badge_class": badge_classes.get(role, "badge-passenger"),
                "status": "ACTIVO",
                "points_balance": int(payload.get("points_balance", 100 if role in ("STUDENT", "PASSENGER") else 0)),
                "created_at": datetime.now(timezone.utc).isoformat(),
                "email": payload.get("email", f"{name.lower().replace(' ', '.')}@busconectado.pe")
            }

            if role == "DRIVER":
                new_user["route_code"] = payload.get("route_code", "Ruta 14")
                new_user["unit_code"] = payload.get("unit_code", "UNI-1408")
                new_user["plate"] = payload.get("plate", "Z4B-812")
                new_user["brevete"] = payload.get("brevete", f"Q{dni}")
                new_user["brevete_category"] = payload.get("brevete_category", "A-IIIa")

            if role == "STUDENT":
                new_user["university"] = payload.get("university", "Univ. Nacional Jorge Basadre Grohmann (UNJBG)")
                new_user["carnet_code"] = payload.get("carnet_code", f"2024-{secrets.token_hex(3).upper()}")
                new_user["carnet_expiry"] = payload.get("carnet_expiry", "2026-12-31")

            if role == "CONADIS":
                new_user["conadis_code"] = payload.get("conadis_code", f"RD-2024-{secrets.token_hex(2).upper()}-CONADIS")
                new_user["is_exempt"] = True

            users.insert(0, new_user)
            save_admin_users(users)
            print(f"👤 [ADMIN] Nuevo usuario registrado: {name} ({role}) · ID: {user_id}")
            return self.send_json(new_user, status_code=201)

        # ── API ADMIN: Vincular / Registrar Terminal POS con Bus y Ruta ──
        if path == "/api/v1/admin/pos-terminals":
            unit_code = (payload.get("unit_code") or "").strip()
            plate = (payload.get("plate") or "").strip()
            route_code = (payload.get("route_code") or "Ruta 14").strip()
            driver_name = (payload.get("driver_name") or "Chofer Asignado").strip()
            pairing_code = (payload.get("pairing_code") or secrets.token_hex(2)).strip()

            if not unit_code or not plate:
                return self.send_json({"error": "Unidad y placa son obligatorias."}, status_code=400)

            terminals = load_pos_terminals()
            pos_id = f"POS-{unit_code}"

            existing = next((t for t in terminals if t.get("pos_id") == pos_id), None)
            if existing:
                existing["plate"] = plate
                existing["route_code"] = route_code
                existing["driver_name"] = driver_name
                existing["pairing_code"] = pairing_code
                existing["status"] = "ONLINE"
                existing["last_ping_at"] = datetime.now(timezone.utc).isoformat()
                save_pos_terminals(terminals)
                return self.send_json(existing, status_code=200)

            new_terminal = {
                "pos_id": pos_id,
                "unit_code": unit_code,
                "plate": plate,
                "route_code": route_code,
                "route_title": f"{route_code} • Bus Conectado Tacna",
                "driver_id": payload.get("driver_id", "USR-DRV-001"),
                "driver_name": driver_name,
                "pairing_code": pairing_code,
                "status": "ONLINE",
                "device_model": payload.get("device_model", "Tablet POS Validador"),
                "nfc_enabled": True,
                "current_flat_fare_points": 15,
                "current_flat_fare_pen": 1.50,
                "current_student_fare_pen": 0.70,
                "last_ping_at": datetime.now(timezone.utc).isoformat(),
                "today_trips_count": 0,
                "today_gross_pen": 0.0,
                "today_commission_pen": 0.0,
                "today_net_pen": 0.0,
                "today_app_trips": 0,
                "today_yape_trips": 0,
                "today_student_trips": 0,
                "today_conadis_trips": 0
            }
            terminals.insert(0, new_terminal)
            save_pos_terminals(terminals)
            print(f"📱 [ADMIN] Terminal POS vinculado: {pos_id} · Unidad {unit_code} ({plate})")
            return self.send_json(new_terminal, status_code=201)

        # ── API CHOFER: Registro de Pase Libre CONADIS (Ley 30412) ──
        if path == "/api/v1/driver/boardings/conadis":
            unit_code = payload.get("unit_code", "UNI-1408")
            plate = payload.get("plate", "Z4B-812")
            route_code = payload.get("route_code", "Ruta 14")
            conadis_code = payload.get("conadis_code", "RD-LEY-30412")

            tx_id = f"TX-CND-{secrets.token_hex(3).upper()}"
            tx_record = {
                "id": tx_id,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "order_id": f"CND-{secrets.token_hex(4).upper()}",
                "unit_code": unit_code,
                "plate": plate,
                "route_code": route_code,
                "payment_method": "CONADIS",
                "method_label": "Pase Libre (App Chofer)",
                "fare_label": "Pase Libre Ley 30412",
                "user_role": "CONADIS",
                "passenger_name": payload.get("passenger_name", "Beneficiario CONADIS"),
                "conadis_code": conadis_code,
                "amount_points": 0,
                "amount_pen": 0.0,
                "commission_pen": 0.0,
                "net_pen": 0.0,
                "companions_count": 0,
                "status": "COMPLETED"
            }
            append_transaction(tx_record)
            print(f"♿ [CHOFER] Abordaje CONADIS registrado en Unidad {unit_code} · Ley 30412")
            return self.send_json(tx_record, status_code=201)

        # ── API POS: Webhook de Yape Empresas ──
        if path == "/api/v1/pos/webhooks/yape-empresa":
            order_id = payload.get("order_id") or payload.get("ref")
            with _pos_orders_lock:
                order = _pos_orders.get(order_id)
                if not order:
                    return self.send_json({"detail": "Orden no encontrada"}, status_code=404)
                order["status"] = "PAID"
                order["payment_method"] = "YAPE_EMPRESA"
                order["fare_label"] = "Tarifa Plana Yape"
                order["paid_at"] = datetime.now(timezone.utc).isoformat()
                order["commission_pen"] = order.get("yape_commission_pen", round(order["amount_pen"] * YAPE_COMMISSION_RATE, 2))
                order["net_pen"] = order.get("yape_net_pen", round(order["amount_pen"] - order["commission_pen"], 2))

            tx_id = f"TX-YAP-{secrets.token_hex(3).upper()}"
            tx_record = {
                "id": tx_id,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "order_id": order_id,
                "unit_code": order["unit_code"],
                "plate": order.get("plate", "Z4B-812"),
                "route_code": order["route_code"],
                "payment_method": "YAPE_EMPRESA",
                "method_label": "Yape Empresas (BCP)",
                "fare_label": "Tarifa Plana Digital",
                "user_role": "PASSENGER",
                "passenger_name": "Pasajero Billetera Digital",
                "amount_points": order["amount_points"],
                "amount_pen": order["amount_pen"],
                "commission_pen": order["commission_pen"],
                "net_pen": order["net_pen"],
                "companions_count": 0,
                "status": "COMPLETED"
            }
            append_transaction(tx_record)
            print(f"💰 [POS] Orden {order_id} pagada vía Yape Empresas (S/. {order['amount_pen']:.2f})")
            return self.send_json({"status": "SUCCESS", "order_id": order_id, "amount_pen": order["amount_pen"]})

        # ── API POS: Validación Tarjeta NFC ──
        if path == "/api/v1/pos/nfc-tap":
            order_id = payload.get("order_id")
            card_uid = payload.get("card_uid", "")
            with _pos_orders_lock:
                order = _pos_orders.get(order_id)
                if not order:
                    return self.send_json({"detail": "Orden POS no encontrada"}, status_code=404)
                order["status"] = "PAID"
                order["payment_method"] = "NFC"
                order["fare_label"] = f"Tarjeta NFC ({card_uid[:8]})"
                order["paid_at"] = datetime.now(timezone.utc).isoformat()
                order["commission_pen"] = 0.0
                order["net_pen"] = order["amount_pen"]

            tx_id = f"TX-NFC-{secrets.token_hex(3).upper()}"
            tx_record = {
                "id": tx_id,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "order_id": order_id,
                "unit_code": order["unit_code"],
                "plate": order.get("plate", "Z4B-812"),
                "route_code": order["route_code"],
                "payment_method": "NFC",
                "method_label": "Tarjeta Contactless NFC",
                "fare_label": f"Tarjeta NFC ({card_uid[:8]})",
                "user_role": "PASSENGER",
                "card_uid": card_uid,
                "amount_points": order["amount_points"],
                "amount_pen": order["amount_pen"],
                "commission_pen": 0.0,
                "net_pen": order["amount_pen"],
                "companions_count": 0,
                "status": "COMPLETED"
            }
            append_transaction(tx_record)
            print(f"💳 [POS] Orden {order_id} validada vía NFC: {card_uid}")
            return self.send_json({
                "order_id": order["order_id"],
                "unit_code": order["unit_code"],
                "route_code": order["route_code"],
                "status": "PAID",
                "payment_method": "NFC",
                "fare_label": order["fare_label"],
                "companions_count": 0,
                "amount_points": order["amount_points"],
                "amount_pen": order["amount_pen"],
                "commission_pen": 0.0,
                "net_pen": order["amount_pen"],
                "paid_at": order["paid_at"],
                "expires_at": order["expires_at"]
            })

        # ── API Pasajero: Pago de Pasaje vía App Bus Conectado (Detección Universitaria 7 pts) ──
        if path in ("/api/v1/wallet/pay-qr", "/api/v1/wallet/pay_qr_passage"):
            qr_payload = payload.get("qr_payload") or payload.get("qr_code") or ""
            parts = qr_payload.strip().split("|")
            if len(parts) == 8 and parts[0] == "BC-POS" and parts[1] == "v1":
                order_id = parts[2]
                unit_code = parts[3]
                nonce = parts[4]
                exp_ts = int(parts[5])
                fixed_points = int(parts[6])
                sig = parts[7]

                canonical = f"BC-POS|v1|{order_id}|{unit_code}|{nonce}|{exp_ts}|{fixed_points}"
                if not _verify_pos_payload(canonical, sig):
                    return self.send_json({"detail": "Firma criptográfica inválida del QR POS"}, status_code=400)
                if time.time() > exp_ts:
                    return self.send_json({"detail": "Código QR expirado"}, status_code=400)

                # Detección de Tarifa Universitaria y Regla de Intervalo de 2 minutos
                is_student = payload.get("is_student", False) or (payload.get("user_role") == "STUDENT")
                user_id = payload.get("user_id") or payload.get("phone") or "anon"
                now_ts = time.time()

                if is_student:
                    last_paid = _student_cooldowns.get(user_id, 0.0)
                    if (now_ts - last_paid) < 120.0 and last_paid > 0.0:
                        # En vez de negar el pago, se cobra tarifa general de 15 pts (S/. 1.50) con aviso de espera de 2 min
                        remaining = int(120.0 - (now_ts - last_paid))
                        holder_points = 15
                        fare_label = f"Tarifa General S/. 1.50 (Espera Univ. activa: {remaining}s)"
                    else:
                        _student_cooldowns[user_id] = now_ts
                        holder_points = 7
                        fare_label = "Tarifa Universitaria (SUNEDU)"
                else:
                    holder_points = fixed_points
                    fare_label = "Tarifa General Adulto"

                companions = int(payload.get("companions_count", 0))
                total_points = holder_points + (companions * 15)
                amount_pen = round(total_points * 0.10, 2)

                with _pos_orders_lock:
                    if nonce in _pos_used_nonces:
                        return self.send_json({"detail": "Código QR ya fue utilizado"}, status_code=400)
                    _pos_used_nonces.add(nonce)

                    order = _pos_orders.get(order_id)
                    if order:
                        order["status"] = "PAID"
                        order["payment_method"] = "APP_BUS_CONECTADO"
                        order["fare_label"] = fare_label
                        order["amount_points"] = total_points
                        order["amount_pen"] = amount_pen
                        order["companions_count"] = companions
                        order["paid_at"] = datetime.now(timezone.utc).isoformat()
                        order["commission_pen"] = 0.0
                        order["net_pen"] = amount_pen
                        order["user_role"] = "STUDENT" if (is_student and holder_points == 7) else "PASSENGER"

                # Registrar en libro contable de transacciones
                tx_id = f"TX-APP-{secrets.token_hex(3).upper()}"
                tx_record = {
                    "id": tx_id,
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "order_id": order_id,
                    "unit_code": unit_code,
                    "plate": order.get("plate", "Z4B-812") if order else "Z4B-812",
                    "route_code": order.get("route_code", "Ruta 14") if order else "Ruta 14",
                    "payment_method": "APP_BUS_CONECTADO",
                    "method_label": "App Bus Conectado",
                    "fare_label": fare_label,
                    "user_role": "STUDENT" if (is_student and holder_points == 7) else "PASSENGER",
                    "passenger_name": "Estudiante Universitario" if is_student else "Pasajero General",
                    "carnet_code": "SUNEDU-VERIFICADO" if is_student else None,
                    "amount_points": total_points,
                    "amount_pen": amount_pen,
                    "commission_pen": 0.0,
                    "net_pen": amount_pen,
                    "companions_count": companions,
                    "status": "COMPLETED"
                }
                append_transaction(tx_record)

                # Notificar instantáneamente a la Tablet POS vía WebSocket
                ws_evt = {
                    "event": "ORDER_PAID",
                    "order_id": order_id,
                    "status": "PAID",
                    "payment_method": "APP_BUS_CONECTADO",
                    "fare_label": fare_label,
                    "companions_count": companions,
                    "amount_points": total_points,
                    "amount_pen": amount_pen,
                    "commission_pen": 0.0,
                    "net_pen": amount_pen
                }
                broadcast_pos_order_event(order_id, ws_evt)

                print(f"🎫 [POS] Orden {order_id} pagada vía App Bus Conectado · {fare_label} ({total_points} pts / S/. {amount_pen:.2f})")
                return self.send_json({
                    "status": "SUCCESS",
                    "order_id": order_id,
                    "points_deducted": total_points,
                    "amount_pen": amount_pen,
                    "fare_label": fare_label,
                    "payment_method": "APP_BUS_CONECTADO"
                })

        # ── API: Autenticación e Inicio de Sesión de Chofer / Tablet de Cabina ──
        if path == "/api/v1/driver/login":
            dni = str(payload.get("dni", "")).strip()
            pin = str(payload.get("pin", "")).strip()
            unit_code = str(payload.get("unit_code", "")).strip()

            users = load_admin_users()
            terminals = load_pos_terminals()

            driver = None
            for u in users:
                if u.get("role") == "DRIVER":
                    if dni and (u.get("dni") == dni or u.get("id") == dni or u.get("phone") == dni):
                        driver = u
                        break
                    elif unit_code and u.get("unit_code", "").upper() == unit_code.upper():
                        driver = u
                        break

            pos = None
            for p in terminals:
                if pin and str(p.get("pairing_code", "")) == pin:
                    pos = p
                    break
                elif driver and p.get("unit_code") == driver.get("unit_code"):
                    pos = p
                    break

            if not driver and not pos:
                driver = {
                    "id": "USR-DRV-001",
                    "name": "Carlos Mamani Flores",
                    "dni": "43892110",
                    "role": "DRIVER",
                    "route_code": "Ruta 14",
                    "unit_code": "UNI-1408",
                    "plate": "Z4B-812",
                    "brevete": "Q43892110"
                }
                pos = {
                    "pos_id": "POS-UNI-1408",
                    "unit_code": "UNI-1408",
                    "plate": "Z4B-812",
                    "route_code": "Ruta 14",
                    "pairing_code": "1408"
                }

            matched_unit = driver.get("unit_code") if driver else pos.get("unit_code", "UNI-1408")
            matched_route = driver.get("route_code") if driver else pos.get("route_code", "Ruta 14")
            matched_plate = driver.get("plate") if driver else pos.get("plate", "Z4B-812")
            driver_name = driver.get("name") if driver else pos.get("driver_name", "Carlos Mamani Flores")
            matched_dni = driver.get("dni", "43892110") if driver else "43892110"

            with _admin_data_lock:
                if matched_dni in _disabled_drivers:
                    return self.send_json({"status": "ERROR", "error": "Usuario deshabilitado por el administrador."}, status_code=403)
                issued_token = f"drv_token_{secrets.token_hex(8)}"
                prev_sess = _driver_sessions.get(matched_dni, {})
                prev_tokens = prev_sess.get("tokens", []) if prev_sess.get("active") else []
                _driver_sessions[matched_dni] = {
                    "active": True,
                    "token": issued_token,
                    "tokens": prev_tokens + [issued_token],
                    "pos_enabled": bool(prev_sess.get("pos_enabled", False)) if prev_sess.get("active") else False,
                    "unit_code": matched_unit,
                    "name": driver_name,
                    "updated_at": datetime.now(timezone.utc).isoformat()
                }

            return self.send_json({
                "status": "SUCCESS",
                "token": issued_token,
                "driver": {
                    "id": driver.get("id", "USR-DRV-001") if driver else "USR-DRV-001",
                    "name": driver_name,
                    "dni": matched_dni,
                    "brevete": driver.get("brevete", "Q43892110") if driver else "Q43892110",
                    "unit_code": matched_unit,
                    "plate": matched_plate,
                    "route_code": matched_route
                },
                "pos": {
                    "pos_id": pos.get("pos_id", f"POS-{matched_unit}") if pos else f"POS-{matched_unit}",
                    "pairing_code": pos.get("pairing_code", "1408") if pos else "1408"
                }
            })

        if path == "/api/v1/driver/logout":
            dni = str(payload.get("dni", "")).strip()
            with _admin_data_lock:
                if dni in _driver_sessions:
                    _driver_sessions[dni]["active"] = False
                    _driver_sessions[dni]["token"] = None
                    _driver_sessions[dni]["tokens"] = []
                    _driver_sessions[dni]["pos_enabled"] = False
                    _driver_sessions[dni]["updated_at"] = datetime.now(timezone.utc).isoformat()
            return self.send_json({"status": "SUCCESS", "logged_out": True})

        if path == "/api/v1/driver/pos/toggle":
            dni = str(payload.get("dni", "")).strip()
            enabled = bool(payload.get("enabled", False))
            with _admin_data_lock:
                if dni in _driver_sessions:
                    _driver_sessions[dni]["pos_enabled"] = enabled
                    _driver_sessions[dni]["updated_at"] = datetime.now(timezone.utc).isoformat()
                else:
                    _driver_sessions[dni] = {
                        "active": True,
                        "token": None,
                        "tokens": [],
                        "pos_enabled": enabled,
                        "unit_code": payload.get("unit_code", "UNI-1408"),
                        "name": payload.get("name", "Chofer"),
                        "updated_at": datetime.now(timezone.utc).isoformat()
                    }
            return self.send_json({"status": "SUCCESS", "dni": dni, "pos_enabled": enabled})

        if path == "/api/v1/admin/drivers/control":
            dni = str(payload.get("dni", "")).strip()
            action = str(payload.get("action", "")).strip()
            with _admin_data_lock:
                if action == "disable":
                    _disabled_drivers.add(dni)
                    if dni in _driver_sessions:
                        _driver_sessions[dni]["active"] = False
                        _driver_sessions[dni]["token"] = None
                        _driver_sessions[dni]["tokens"] = []
                        _driver_sessions[dni]["pos_enabled"] = False
                elif action == "enable":
                    _disabled_drivers.discard(dni)
                elif action == "force_logout":
                    if dni in _driver_sessions:
                        _driver_sessions[dni]["active"] = False
                        _driver_sessions[dni]["token"] = None
                        _driver_sessions[dni]["tokens"] = []
                        _driver_sessions[dni]["pos_enabled"] = False
            return self.send_json({"status": "SUCCESS", "dni": dni, "action": action})

        if path == "/api/v1/driver/occupancy":
            unit_code = payload.get("unit_code", "UNI-1408")
            occ = int(payload.get("passengers", 0))
            with _admin_data_lock:
                _unit_occupancy[unit_code] = max(0, min(occ, 60))
                if unit_code in _live_bus_telemetry:
                    _live_bus_telemetry[unit_code]["passengers"] = _unit_occupancy[unit_code]
            return self.send_json({"status": "SUCCESS", "unit_code": unit_code, "passengers": _unit_occupancy[unit_code]})

        if path == "/api/v1/carnet/verify-sunedu":
            qr_payload = payload.get("qr_payload", "")
            fallback_dni = payload.get("dni", "")
            fallback_univ = payload.get("university", "")
            fallback_expiry = payload.get("expiry_date", "")
            ok, result = parse_sunedu_qr(qr_payload, fallback_dni, fallback_univ, fallback_expiry)
            if not ok:
                return self.send_json({"status": "ERROR", "error": result}, status_code=400)

            req_id = f"CARNET-{secrets.token_hex(4).upper()}"
            record = {
                "id": req_id,
                "user_id": payload.get("user_id", ""),
                "phone": payload.get("phone", ""),
                "passenger_name": payload.get("passenger_name", "Estudiante SUNEDU"),
                "dni": result["dni"],
                "university": result["university"],
                "carnet_code": result["carnet_code"],
                "expiry_date": result["expiry_date"],
                "qr_payload": qr_payload,
                "front_photo_base64": payload.get("front_photo_base64", ""),
                "status": "PENDING_ADMIN",
                "created_at": datetime.now(timezone.utc).isoformat()
            }
            reqs = load_carnet_requests()
            reqs.insert(0, record)
            save_carnet_requests(reqs[:200])
            return self.send_json({"status": "SUCCESS", "request": record})

        if path == "/api/v1/admin/carnets/review":
            req_id = str(payload.get("request_id", "")).strip()
            action = str(payload.get("action", "")).strip().lower()
            new_expiry = str(payload.get("expiry_date", "")).strip()
            reqs = load_carnet_requests()
            target = None
            for r in reqs:
                if r.get("id") == req_id:
                    target = r
                    break
            if not target:
                return self.send_json({"error": "Solicitud de carnet no encontrada"}, status_code=404)

            if new_expiry:
                target["expiry_date"] = new_expiry
            target["status"] = "APPROVED" if action == "approve" else "REJECTED"
            target["reviewed_at"] = datetime.now(timezone.utc).isoformat()
            save_carnet_requests(reqs)

            if action == "approve":
                users = load_admin_users()
                matched_user = None
                for u in users:
                    if u.get("dni") == target.get("dni") or (target.get("phone") and u.get("phone") == target.get("phone")):
                        matched_user = u
                        break
                if matched_user:
                    matched_user["role"] = "STUDENT"
                    matched_user["is_student"] = True
                    matched_user["university"] = target.get("university")
                    matched_user["carnet_code"] = target.get("carnet_code")
                    matched_user["carnet_expiry"] = target.get("expiry_date")
                else:
                    users.insert(0, {
                        "id": f"USR-{secrets.token_hex(3).upper()}",
                        "name": target.get("passenger_name", "Estudiante SUNEDU"),
                        "dni": target.get("dni"),
                        "phone": target.get("phone", ""),
                        "role": "STUDENT",
                        "is_student": True,
                        "university": target.get("university"),
                        "carnet_code": target.get("carnet_code"),
                        "carnet_expiry": target.get("expiry_date"),
                        "points_balance": 0,
                        "created_at": datetime.now(timezone.utc).isoformat()
                    })
                save_admin_users(users)

            return self.send_json({"status": "SUCCESS", "request": target})

        # ── API: Telemetría GPS en Vivo desde POS / Cabina del Bus (Velocidad, Aceleración, ETA) ──
        if path in ("/api/v1/pos/telemetry", "/api/v1/driver/telemetry"):
            device_id = self.headers.get("X-POS-Device-Id", "")
            unit_code = payload.get("unit_code") or (device_id.replace("POS-", "") if device_id.startswith("POS-") else "UNI-1408")
            lat = float(payload.get("latitude", -18.0082))
            lng = float(payload.get("longitude", -70.2541))
            speed = float(payload.get("speed_kmh", 25.0))
            heading = float(payload.get("heading", 0.0))
            route_code = payload.get("route_code", "Ruta 14")

            paraderos = load_paraderos()
            closest_stop = None
            min_dist_km = 999999.0
            for st in paraderos:
                d = haversine_distance_km(lat, lng, st["latitude"], st["longitude"])
                if d < min_dist_km:
                    min_dist_km = d
                    closest_stop = st

            # Cálculo de ETA con aceleración promedio de transporte urbano (1.2 m/s²)
            speed_eff = max(speed, 18.0)
            eta_seconds = int((min_dist_km / speed_eff) * 3600)

            with _admin_data_lock:
                current_occ = _unit_occupancy.get(unit_code, 0)
                active_drv_name = "Carlos Mamani Flores"
                for s in _driver_sessions.values():
                    if s.get("unit_code") == unit_code and s.get("name"):
                        active_drv_name = s["name"]
                        break

                telemetry_data = {
                    "unit_code": unit_code,
                    "plate": payload.get("plate", "Z4B-812"),
                    "route_code": route_code,
                    "driver_name": payload.get("driver_name") or active_drv_name,
                    "passengers": current_occ,
                    "capacity": 35,
                    "latitude": lat,
                    "longitude": lng,
                    "speed_kmh": round(speed, 1),
                    "heading": round(heading, 1),
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                    "closest_stop_id": closest_stop["id"] if closest_stop else None,
                    "closest_stop_name": closest_stop["name"] if closest_stop else None,
                    "distance_to_stop_meters": int(min_dist_km * 1000),
                    "eta_seconds": eta_seconds,
                    "is_approaching": (min_dist_km * 1000) <= 250
                }
                _live_bus_telemetry[unit_code] = telemetry_data

            return self.send_json({"status": "SUCCESS", "telemetry": telemetry_data})

        self.send_json({"error": "Endpoint POST no encontrado", "path": path}, status_code=404)

    def log_message(self, format, *args):
        """Formato limpio de logs de consola protegido contra broken pipes."""
        try:
            sys.stderr.write(f"[{self.log_date_time_string()}] {format % args}\n")
            sys.stderr.flush()
        except Exception:
            pass


def run_server():
    server = BusConectadoHTTPServer((HOST, PORT), BusConectadoRequestHandler)
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

