from fastapi import APIRouter
from app.api.v1.endpoints import auth, wallet, transit

api_router = APIRouter()

api_router.include_router(auth.router, prefix="/auth", tags=["Autenticación y Cuentas de Prueba (CU-00)"])
api_router.include_router(wallet.router, prefix="/wallet", tags=["Monedero, SUNEDU y Pagos QR (CU-01 / CU-03 / CU-05 / CU-08)"])
api_router.include_router(transit.router, prefix="/transit", tags=["Rutas, Paraderos y Telemetría (CU-07)"])
