"""/v1/track — lookup-first, populate-on-miss (ARCHITECTURE §6, Phase 3 consumer).

GET   /v1/track?isrc=… | ?fingerprint=…   → facts or 404
POST  /v1/track                            → populate (201 created | 200 existing)
POST  /v1/track/batch                      → bulk lookup for library import
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from .. import crud
from ..db import get_session
from ..schemas import (
    BatchLookupIn,
    BatchLookupItem,
    BatchLookupResponse,
    ConfirmIn,
    PopulateResponse,
    TrackFactsIn,
    TrackFactsOut,
)

router = APIRouter(prefix="/v1/track", tags=["track-table"])


@router.get("", response_model=TrackFactsOut)
async def lookup(
    isrc: str | None = Query(default=None, max_length=15),
    fingerprint: str | None = Query(default=None),
    session: AsyncSession = Depends(get_session),
) -> TrackFactsOut:
    if not isrc and not fingerprint:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="provide isrc or fingerprint",
        )
    row = await crud.get_by_identity(session, isrc=isrc, fingerprint=fingerprint)
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="miss")
    return TrackFactsOut.model_validate(row)


@router.post("", response_model=PopulateResponse)
async def populate(
    data: TrackFactsIn,
    response: Response,
    session: AsyncSession = Depends(get_session),
) -> PopulateResponse:
    row, created = await crud.populate(session, data)
    response.status_code = status.HTTP_201_CREATED if created else status.HTTP_200_OK
    return PopulateResponse(created=created, track=TrackFactsOut.model_validate(row))


@router.post("/{track_id}/confirm", response_model=TrackFactsOut)
async def confirm(
    track_id: str,
    body: ConfirmIn,
    session: AsyncSession = Depends(get_session),
) -> TrackFactsOut:
    """Objective feedback (skip-at-tempo / off-tempo / corroboration). Enough
    independent corroboration can correct a low-confidence reading — for everyone."""
    facts = await crud.confirm(session, track_id, body)
    if facts is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="unknown track")
    return TrackFactsOut.model_validate(facts)


@router.post("/batch", response_model=BatchLookupResponse)
async def batch_lookup(
    body: BatchLookupIn,
    session: AsyncSession = Depends(get_session),
) -> BatchLookupResponse:
    """One round trip resolves a whole library: hits return facts, misses return null.

    The client then analyzes only the misses in the background (Phase 3).
    """
    results: list[BatchLookupItem] = []
    for key in body.keys:
        row = await crud.get_by_identity(
            session, isrc=key.isrc, fingerprint=key.fingerprint
        )
        results.append(
            BatchLookupItem(
                key=key,
                hit=row is not None,
                track=TrackFactsOut.model_validate(row) if row is not None else None,
            )
        )
    return BatchLookupResponse(results=results)
