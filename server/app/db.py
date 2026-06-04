"""Async SQLAlchemy engine/session wiring.

Portable across Postgres (asyncpg) and SQLite (aiosqlite) so the same models
serve production and tests without change.
"""
from __future__ import annotations

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


def init_engine(database_url: str, **engine_kwargs) -> AsyncEngine:
    """(Re)build the global engine + sessionmaker. Tests call this with SQLite."""
    global _engine, _sessionmaker
    _engine = create_async_engine(database_url, future=True, **engine_kwargs)
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
