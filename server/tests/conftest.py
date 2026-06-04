"""Test harness: in-memory SQLite (shared via StaticPool) + an ASGI httpx client.

No Postgres needed to run the suite; the models are portable.
"""
from __future__ import annotations

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.pool import StaticPool

from app.db import create_all, init_engine
from app.main import app


@pytest_asyncio.fixture
async def client() -> AsyncClient:
    # Fresh in-memory DB per test. StaticPool keeps the single connection alive so
    # the schema persists across sessions within the test.
    init_engine(
        "sqlite+aiosqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    await create_all()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
