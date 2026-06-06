"""Async SQLAlchemy engine/session wiring.

Portable across Postgres (asyncpg) and SQLite (aiosqlite) so the same models
serve production and tests without change.
"""
from __future__ import annotations

import ssl
from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


_engine: AsyncEngine | None = None
_sessionmaker: async_sessionmaker[AsyncSession] | None = None


def _managed_pg_connect_args(database_url: str) -> dict:
    """Supabase (and most managed Postgres) require TLS. Detect by host and hand
    asyncpg an SSL context. Local SQLite and the Docker `db` host need nothing,
    so they fall through untouched.

    Supabase's connection pooler presents a private (self-signed) CA that the public
    trust store / certifi can't verify, so we encrypt without chain verification —
    libpq `sslmode=require` semantics. To harden to verify-full, download Supabase's
    CA cert (Dashboard → Database → SSL configuration) and pass it as `cafile=` to a
    verifying context instead.
    """
    if database_url.startswith("postgresql+asyncpg") and "supabase." in database_url:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return {"connect_args": {"ssl": ctx}}
    return {}


def init_engine(database_url: str, **engine_kwargs) -> AsyncEngine:
    """(Re)build the global engine + sessionmaker. Tests call this with SQLite."""
    global _engine, _sessionmaker
    # Caller-supplied kwargs win over the auto-detected managed-Postgres defaults.
    kwargs = {**_managed_pg_connect_args(database_url), **engine_kwargs}
    _engine = create_async_engine(database_url, future=True, **kwargs)
    _sessionmaker = async_sessionmaker(_engine, expire_on_commit=False)
    return _engine


async def create_all() -> None:
    assert _engine is not None, "init_engine() must run first"
    async with _engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def get_session() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency — one session per request."""
    assert _sessionmaker is not None, "init_engine() must run first"
    async with _sessionmaker() as session:
        yield session
