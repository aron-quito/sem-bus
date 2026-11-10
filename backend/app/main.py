from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.api.v1.router import api_router
from app.core.redis import get_redis_pool


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Inicializar conexión con Redis
    pool = None
    try:
        pool = get_redis_pool()
    except Exception as e:
        print(f"[WARN] No se pudo inicializar el pool de Redis: {e}")
    yield
    # Shutdown: Cerrar conexiones
    if pool:
        try:
            await pool.disconnect()
        except Exception:
            pass


app = FastAPI(
    title=settings.APP_NAME,
    description="API Central de Transporte Urbano Automatizado - Tacna, Perú. Arquitectura SWEBOK v4.",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/api/v1/openapi.json",
    lifespan=lifespan,
)

# Configuración de CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Montar Router de la API v1
app.include_router(api_router, prefix="/api/v1")


@app.get("/health", tags=["Health"])
async def health_check():
    return {
        "status": "healthy",
        "app": settings.APP_NAME,
        "environment": settings.ENV,
        "version": "1.0.0",
    }

