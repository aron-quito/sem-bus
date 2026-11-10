from typing import AsyncGenerator
import redis.asyncio as aioredis
from app.core.config import settings

redis_pool = None


def get_redis_pool():
    global redis_pool
    if redis_pool is None:
        redis_pool = aioredis.ConnectionPool.from_url(
            settings.REDIS_URL,
            decode_responses=True,
            max_connections=50,
        )
    return redis_pool


async def get_redis() -> AsyncGenerator[aioredis.Redis, None]:
    """Dependency generator para inyección del cliente Redis asíncrono."""
    pool = get_redis_pool()
    client = aioredis.Redis(connection_pool=pool)
    try:
        yield client
    finally:
        await client.aclose()

