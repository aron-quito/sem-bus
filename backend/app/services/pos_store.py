import asyncio
import json
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

import redis.asyncio as aioredis
from fastapi import WebSocket

from app.core.config import settings
from app.core.redis import get_redis_pool


def compute_commission_breakdown(amount_pen: float, method: str) -> Dict[str, float]:
    """
    Calcula la comisión y el neto recibido para el operador del bus:
    - APP_QR / NFC: 0% de comisión bancaria en puerta (la recarga se procesa aparte).
    - YAPE_EMPRESA: 2.95% diario sobre ventas totales (sin tarifa mínima fija por pasaje).
    """
    normalized = method.upper()
    if normalized in ("YAPE", "YAPE_EMPRESA", "PLIN"):
        commission = round(amount_pen * settings.YAPE_EMPRESA_COMMISSION_RATE, 4)
        net = round(amount_pen - commission, 4)
        return {
            "commission_rate": settings.YAPE_EMPRESA_COMMISSION_RATE,
            "commission_pen": round(commission, 2),
            "net_pen": round(net, 2),
        }
    return {
        "commission_rate": 0.0,
        "commission_pen": 0.0,
        "net_pen": round(amount_pen, 2),
    }


class PosOrderStore:
    """
    Almacén de órdenes POS y nonces anti-replay.
    Usa Redis atómico (SET NX / GETDEL) en producción, con respaldo en memoria para dev sin Redis.
    """

    def __init__(self) -> None:
        self._mem_lock = asyncio.Lock()
        self._mem_orders: Dict[str, Dict[str, Any]] = {}
        self._mem_nonces: Dict[str, int] = {}
        self._ws_connections: Dict[str, List[WebSocket]] = {}

    async def _redis(self) -> Optional[aioredis.Redis]:
        try:
            client = aioredis.Redis(connection_pool=get_redis_pool())
            await client.ping()
            return client
        except Exception:
            return None

    async def save_order(self, order: Dict[str, Any], ttl_seconds: int = 300) -> None:
        order_id = order["order_id"]
        unit_code = order["unit_code"]
        amount_cents = int(round(float(order["amount_pen"]) * 100))
        client = await self._redis()
        if client is not None:
            try:
                await client.set(f"pos:order:{order_id}", json.dumps(order), ex=ttl_seconds)
                if order["status"] == "PENDING":
                    await client.sadd(f"pos:pending_yape:{unit_code}:{amount_cents}", order_id)
                    await client.expire(f"pos:pending_yape:{unit_code}:{amount_cents}", ttl_seconds)
                return
            finally:
                await client.aclose()

        async with self._mem_lock:
            self._mem_orders[order_id] = dict(order)

    async def get_order(self, order_id: str) -> Optional[Dict[str, Any]]:
        client = await self._redis()
        raw: Optional[str] = None
        if client is not None:
            try:
                raw = await client.get(f"pos:order:{order_id}")
            finally:
                await client.aclose()
        else:
            async with self._mem_lock:
                cached = self._mem_orders.get(order_id)
                raw = json.dumps(cached) if cached else None

        if not raw:
            return None

        order = json.loads(raw)
        now_ts = int(datetime.now(timezone.utc).timestamp())
        if order.get("status") == "PENDING" and now_ts > int(order.get("exp_ts", 0)):
            order["status"] = "EXPIRED"
            await self.save_order(order, ttl_seconds=180)
        return order

    async def find_pending_order_by_unit_and_amount(
        self, unit_code: str, amount_pen: float
    ) -> Optional[Dict[str, Any]]:
        amount_cents = int(round(amount_pen * 100))
        client = await self._redis()
        if client is not None:
            try:
                candidates = await client.smembers(f"pos:pending_yape:{unit_code}:{amount_cents}")
            finally:
                await client.aclose()
            for oid in sorted(candidates):
                order = await self.get_order(oid)
                if order and order.get("status") == "PENDING":
                    return order
            return None

        async with self._mem_lock:
            now_ts = int(datetime.now(timezone.utc).timestamp())
            for order in self._mem_orders.values():
                if (
                    order.get("unit_code") == unit_code
                    and order.get("status") == "PENDING"
                    and int(round(float(order.get("amount_pen", 0)) * 100)) == amount_cents
                    and now_ts <= int(order.get("exp_ts", 0))
                ):
                    return dict(order)
        return None

    async def consume_nonce_once(self, nonce: str, ttl_seconds: int = 120) -> bool:
        """
        Consume el nonce de forma atómica. Devuelve True solo la primera vez;
        cualquier reintento/captura duplicada devuelve False.
        """
        client = await self._redis()
        if client is not None:
            try:
                acquired = await client.set(f"pos:nonce:{nonce}", "1", nx=True, ex=ttl_seconds)
                return bool(acquired)
            finally:
                await client.aclose()

        now_ts = int(datetime.now(timezone.utc).timestamp())
        async with self._mem_lock:
            expired_keys = [k for k, exp in self._mem_nonces.items() if exp < now_ts]
            for k in expired_keys:
                del self._mem_nonces[k]
            if nonce in self._mem_nonces:
                return False
            self._mem_nonces[nonce] = now_ts + ttl_seconds
            return True

    async def mark_order_paid(
        self,
        order_id: str,
        payment_method: str,
        fare_label: str,
        companions_count: int,
        amount_points: int,
        amount_pen: float,
    ) -> Optional[Dict[str, Any]]:
        order = await self.get_order(order_id)
        if not order:
            return None

        if order["status"] == "PAID":
            return order

        breakdown = compute_commission_breakdown(amount_pen, payment_method)
        order["status"] = "PAID"
        order["payment_method"] = payment_method
        order["fare_label"] = fare_label
        order["companions_count"] = companions_count
        order["amount_points"] = amount_points
        order["amount_pen"] = round(amount_pen, 2)
        order["commission_pen"] = breakdown["commission_pen"]
        order["net_pen"] = breakdown["net_pen"]
        order["paid_at"] = datetime.now(timezone.utc).isoformat()

        await self.save_order(order, ttl_seconds=300)
        await self.broadcast_order_event(order_id, {
            "event": "ORDER_PAID",
            "order_id": order_id,
            "status": "PAID",
            "payment_method": payment_method,
            "fare_label": fare_label,
            "companions_count": companions_count,
            "amount_points": amount_points,
            "amount_pen": order["amount_pen"],
            "commission_pen": order["commission_pen"],
            "net_pen": order["net_pen"],
            "paid_at": order["paid_at"],
        })
        return order

    async def cancel_order(self, order_id: str) -> Optional[Dict[str, Any]]:
        order = await self.get_order(order_id)
        if not order:
            return None
        if order["status"] == "PENDING":
            order["status"] = "CANCELLED"
            await self.save_order(order, ttl_seconds=120)
            await self.broadcast_order_event(order_id, {
                "event": "ORDER_CANCELLED",
                "order_id": order_id,
                "status": "CANCELLED",
            })
        return order

    async def register_ws(self, order_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        self._ws_connections.setdefault(order_id, []).append(websocket)

    def unregister_ws(self, order_id: str, websocket: WebSocket) -> None:
        conns = self._ws_connections.get(order_id, [])
        if websocket in conns:
            conns.remove(websocket)
        if not conns and order_id in self._ws_connections:
            del self._ws_connections[order_id]

    async def broadcast_order_event(self, order_id: str, payload: Dict[str, Any]) -> None:
        conns = list(self._ws_connections.get(order_id, []))
        dead: List[WebSocket] = []
        for ws in conns:
            try:
                await ws.send_json(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.unregister_ws(order_id, ws)


pos_store = PosOrderStore()

