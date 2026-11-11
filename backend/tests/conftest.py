import pytest
import pytest_asyncio
from typing import AsyncGenerator
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

from app.main import app
from app.models.base import Base
from app.api.deps import get_db, get_redis

# Base de datos SQLite en memoria para tests rápidos aislados
TEST_DATABASE_URL = "sqlite+aiosqlite:///:memory:"

test_engine = create_async_engine(TEST_DATABASE_URL, echo=False)
test_session_maker = async_sessionmaker(bind=test_engine, class_=AsyncSession, expire_on_commit=False)


class MockPipeline:
    """Simulador de pipeline Redis donde los comandos se encolan de forma síncrona y se ejecutan con await execute()."""
    def __init__(self, redis_mock: "MockRedis"):
        self.redis_mock = redis_mock
        self.ops = []

    def incr(self, key: str):
        self.ops.append(("incr", (key,)))
        return self

    def expire(self, key: str, seconds: int):
        self.ops.append(("expire", (key, seconds)))
        return self

    async def execute(self):
        results = []
        for cmd, args in self.ops:
            method = getattr(self.redis_mock, cmd)
            results.append(await method(*args))
        self.ops.clear()
        return results


class MockRedis:
    """Simulador en memoria de Redis para pruebas unitarias sin dependencias externas."""
    def __init__(self):
        self.store = {}
        self.ttls = {}

    def clear(self):
        self.store.clear()
        self.ttls.clear()

    async def get(self, key: str):
        return self.store.get(key)

    async def set(self, key: str, value: str, ex: int = 300):
        self.store[key] = str(value)
        self.ttls[key] = ex

    async def delete(self, key: str):
        self.store.pop(key, None)
        self.ttls.pop(key, None)

    async def ttl(self, key: str):
        return self.ttls.get(key, -2)

    async def incr(self, key: str):
        val = int(self.store.get(key, 0)) + 1
        self.store[key] = str(val)
        return val

    async def expire(self, key: str, seconds: int):
        self.ttls[key] = seconds

    def pipeline(self):
        return MockPipeline(self)

    async def aclose(self):
        pass


mock_redis_instance = MockRedis()


async def override_get_db() -> AsyncGenerator[AsyncSession, None]:
    async with test_session_maker() as session:
        yield session


async def override_get_redis():
    yield mock_redis_instance


app.dependency_overrides[get_db] = override_get_db
app.dependency_overrides[get_redis] = override_get_redis


@pytest_asyncio.fixture(scope="function", autouse=True)
async def setup_test_db():
    mock_redis_instance.clear()
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    mock_redis_instance.clear()
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)


@pytest_asyncio.fixture
async def client() -> AsyncGenerator[AsyncClient, None]:
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test"
    ) as ac:
        yield ac

