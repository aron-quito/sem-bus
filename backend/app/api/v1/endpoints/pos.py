import hmac
import json
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request, WebSocket, WebSocketDisconnect, status

from app.core.config import settings
from app.core.security import (
    build_yape_empresa_qr_payload,
    generate_nonce,
    sign_pos_qr_payload,
    verify_yape_webhook_signature,
)
from app.schemas.pos import (
    PosNfcTapRequest,
    PosOrderCreateRequest,
    PosOrderResponse,
    PosOrderStatusResponse,
    YapeEmpresaWebhookRequest,
)
from app.services.pos_store import compute_commission_breakdown, pos_store

router = APIRouter()


async def verify_pos_terminal(
    x_pos_device_id: Optional[str] = Header(default=None, alias="X-POS-Device-Id"),
    x_pos_secret: Optional[str] = Header(default=None, alias="X-POS-Secret"),
) -> str:
    """Autenticación de terminal POS en tiempo constante (separa permisos POS de cuentas de pasajero)."""
    if not x_pos_device_id or not x_pos_secret:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Credenciales de terminal POS faltantes.",
        )
    if not hmac.compare_digest(x_pos_secret, settings.POS_DEVICE_SECRET):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Terminal POS no autorizado.",
        )
    return x_pos_device_id


@router.post(
    "/orders",
    response_model=PosOrderResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Generar orden POS única con QR dinámico App + QR Yape Empresa (monto fijo S/. 1.50)"
)
async def create_pos_order(
    payload: PosOrderCreateRequest,
    device_id: str = Depends(verify_pos_terminal),
):
    now = datetime.now(timezone.utc)
    ttl = settings.POS_QR_TTL_SECONDS
    exp_ts = int(now.timestamp()) + ttl
    expires_at_iso = datetime.fromtimestamp(exp_ts, tz=timezone.utc).isoformat()

    order_id = str(uuid.uuid4())
    nonce = generate_nonce()
    points = payload.fixed_amount_points
    amount_pen = round(points / 10.0, 2)

    app_qr_payload = sign_pos_qr_payload(
        order_id=order_id,
        unit_code=payload.unit_code,
        nonce=nonce,
        exp_ts=exp_ts,
        fixed_points=points,
    )
    yape_qr_payload = build_yape_empresa_qr_payload(
        order_id=order_id,
        amount_pen=amount_pen,
    )

    yape_calc = compute_commission_breakdown(amount_pen, "YAPE_EMPRESA")
    app_calc = compute_commission_breakdown(amount_pen, "APP_QR")

    order_record = {
        "order_id": order_id,
        "device_id": device_id,
        "unit_code": payload.unit_code,
        "plate": payload.plate,
        "route_code": payload.route_code,
        "status": "PENDING",
        "amount_points": points,
        "amount_pen": amount_pen,
        "nonce": nonce,
        "exp_ts": exp_ts,
        "expires_at": expires_at_iso,
        "payment_method": None,
        "fare_label": None,
        "companions_count": 0,
        "commission_pen": 0.0,
        "net_pen": 0.0,
        "paid_at": None,
    }
    await pos_store.save_order(order_record, ttl_seconds=ttl + 240)

    return PosOrderResponse(
        order_id=order_id,
        unit_code=payload.unit_code,
        plate=payload.plate,
        route_code=payload.route_code,
        status="PENDING",
        amount_points=points,
        amount_pen=amount_pen,
        ttl_seconds=ttl,
        expires_at=expires_at_iso,
        app_qr_payload=app_qr_payload,
        yape_qr_payload=yape_qr_payload,
        ws_path=f"/api/v1/pos/ws/{order_id}",
        yape_commission_rate=yape_calc["commission_rate"],
        yape_commission_pen=yape_calc["commission_pen"],
        yape_net_pen=yape_calc["net_pen"],
        app_commission_pen=app_calc["commission_pen"],
        app_net_pen=app_calc["net_pen"],
    )


@router.get(
    "/orders/{order_id}",
    response_model=PosOrderStatusResponse,
    summary="Consultar estado de orden POS (sin PII del pasajero)"
)
async def get_pos_order_status(
    order_id: str,
    _: str = Depends(verify_pos_terminal),
):
    order = await pos_store.get_order(order_id)
    if not order:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Orden POS no encontrada.")

    return PosOrderStatusResponse(
        order_id=order["order_id"],
        unit_code=order["unit_code"],
        route_code=order["route_code"],
        status=order["status"],
        payment_method=order.get("payment_method"),
        fare_label=order.get("fare_label"),
        companions_count=int(order.get("companions_count", 0)),
        amount_points=int(order["amount_points"]),
        amount_pen=float(order["amount_pen"]),
        commission_pen=float(order.get("commission_pen", 0.0)),
        net_pen=float(order.get("net_pen", 0.0)),
        paid_at=order.get("paid_at"),
        expires_at=order["expires_at"],
    )


@router.post(
    "/orders/{order_id}/cancel",
    response_model=PosOrderStatusResponse,
    summary="Cancelar orden POS activa"
)
async def cancel_pos_order(
    order_id: str,
    _: str = Depends(verify_pos_terminal),
):
    order = await pos_store.cancel_order(order_id)
    if not order:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Orden POS no encontrada.")

    return PosOrderStatusResponse(
        order_id=order["order_id"],
        unit_code=order["unit_code"],
        route_code=order["route_code"],
        status=order["status"],
        payment_method=order.get("payment_method"),
        fare_label=order.get("fare_label"),
        companions_count=int(order.get("companions_count", 0)),
        amount_points=int(order["amount_points"]),
        amount_pen=float(order["amount_pen"]),
        commission_pen=float(order.get("commission_pen", 0.0)),
        net_pen=float(order.get("net_pen", 0.0)),
        paid_at=order.get("paid_at"),
        expires_at=order["expires_at"],
    )


@router.post(
    "/webhooks/yape-empresa",
    status_code=status.HTTP_200_OK,
    summary="Webhook firmado HMAC-SHA256 para confirmar cobro Yape Empresas a monto fijo"
)
async def receive_yape_empresa_webhook(
    request: Request,
    x_yape_signature: Optional[str] = Header(default=None, alias="X-Yape-Signature"),
):
    raw_bytes = await request.body()
    raw_body = raw_bytes.decode("utf-8")

    if not verify_yape_webhook_signature(raw_body, x_yape_signature or ""):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firma HMAC del webhook Yape inválida.",
        )

    try:
        data = YapeEmpresaWebhookRequest.model_validate(json.loads(raw_body))
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Payload de webhook inválido.") from exc

    # Idempotencia por código de operación Yape (evita acreditar 2 veces un mismo yapeo)
    if not await pos_store.consume_nonce_once(f"yape_op:{data.operation_code}", ttl_seconds=3600):
        return {"success": True, "duplicate": True, "message": "Operación Yape ya procesada."}

    order = None
    if data.order_id:
        order = await pos_store.get_order(data.order_id)
    elif data.unit_code:
        order = await pos_store.find_pending_order_by_unit_and_amount(data.unit_code, data.amount_pen)

    if not order:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No hay orden POS pendiente coincidente para este monto.",
        )

    if order["status"] != "PENDING":
        return {"success": True, "status": order["status"], "message": "La orden ya fue cerrada previamente."}

    expected_pen = round(float(order["amount_pen"]), 2)
    received_pen = round(float(data.amount_pen), 2)
    if abs(expected_pen - received_pen) > 0.01:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Monto recibido (S/. {received_pen:.2f}) no coincide con monto fijo (S/. {expected_pen:.2f}).",
        )

    updated = await pos_store.mark_order_paid(
        order_id=order["order_id"],
        payment_method="YAPE_EMPRESA",
        fare_label="Yape Empresa (Tarifa Plana)",
        companions_count=0,
        amount_points=int(round(received_pen * 10)),
        amount_pen=received_pen,
    )
    return {
        "success": True,
        "order_id": updated["order_id"],
        "status": updated["status"],
        "commission_pen": updated["commission_pen"],
        "net_pen": updated["net_pen"],
    }


@router.post(
    "/nfc-tap",
    status_code=status.HTTP_501_NOT_IMPLEMENTED,
    summary="Endpoint reservado para validación de tarjetas NFC sin contacto en el mismo POS"
)
async def pos_nfc_tap(
    payload: PosNfcTapRequest,
    _: str = Depends(verify_pos_terminal),
):
    order = await pos_store.get_order(payload.order_id)
    if not order or order.get("status") != "PENDING":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Orden POS no vigente para lectura NFC.")
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Lector NFC listo en terminal POS; vinculación de tarjetas físicas pendiente de alta de padrón.",
    )


@router.websocket("/ws/{order_id}")
async def pos_order_websocket(
    websocket: WebSocket,
    order_id: str,
    token: str = Query(default=""),
):
    if not hmac.compare_digest(token, settings.POS_DEVICE_SECRET):
        await websocket.close(code=1008)
        return

    await pos_store.register_ws(order_id, websocket)
    try:
        current = await pos_store.get_order(order_id)
        if current and current.get("status") != "PENDING":
            await websocket.send_json({
                "event": f"ORDER_{current['status']}",
                "order_id": order_id,
                "status": current["status"],
                "payment_method": current.get("payment_method"),
                "fare_label": current.get("fare_label"),
                "companions_count": current.get("companions_count", 0),
                "amount_points": current.get("amount_points", 0),
                "amount_pen": current.get("amount_pen", 0.0),
                "commission_pen": current.get("commission_pen", 0.0),
                "net_pen": current.get("net_pen", 0.0),
                "paid_at": current.get("paid_at"),
            })
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        pos_store.unregister_ws(order_id, websocket)
    except Exception:
        pos_store.unregister_ws(order_id, websocket)

