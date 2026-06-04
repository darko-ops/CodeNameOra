"""Dromo Global Track Table API entrypoint.

Run locally:  uvicorn app.main:app --reload   (from the server/ dir)
"""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI

from .config import settings
from .db import create_all, init_engine
from .routers import health, tracks


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_engine(settings.database_url)
    await create_all()  # v1: create_all. Swap to Alembic migrations before scale.
    yield


app = FastAPI(
    title="Dromo Global Track Table",
    version="1.0.0",
    summary="Facts-only, crowd-built per-recording metadata. No audio ever leaves a device.",
    lifespan=lifespan,
)

app.include_router(health.router)
app.include_router(tracks.router)
