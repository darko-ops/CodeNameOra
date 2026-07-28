"""Data access for the Global Track Table.

Populate is **first-write-wins** on the facts themselves (analyze-once-globally,
ARCHITECTURE §3/§6): a recording analyzed by the first device is not overwritten
by later identical analyses. We do backfill a missing identity key (e.g. a later
submission carries the ISRC the first one lacked). Objective correction of
low-confidence readings is Phase 6, not here.
"""
from __future__ import annotations

from sqlalchemy import case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from .models import TrackConfirmation, TrackFacts
from .schemas import ConfirmIn, TrackFactsIn

# --- Anti-poisoning constants (Phase 6 A1 / §8) ---
# Independent clients required before crowd feedback can override a reading.
MIN_CORROBORATION = 3
# We only override *low-confidence* auto-readings — never confident facts.
CONFIDENCE_OVERRIDE_THRESHOLD = 0.5
# Corrected BPM observations must cluster this tightly (BPM) to count as agreement.
CORRECTION_TOLERANCE = 4.0


async def get_by_identity(
    session: AsyncSession, *, isrc: str | None = None, fingerprint: str | None = None
) -> TrackFacts | None:
    """Lookup by ISRC first (preferred), else by fingerprint."""
    if isrc:
        row = await session.scalar(select(TrackFacts).where(TrackFacts.isrc == isrc))
        if row:
            return row
    if fingerprint:
        return await session.scalar(
            select(TrackFacts).where(TrackFacts.fingerprint == fingerprint)
        )
    return None


async def populate(session: AsyncSession, data: TrackFactsIn) -> tuple[TrackFacts, bool]:
    """Insert facts on miss; on hit return existing (first-write-wins) + backfill id keys.

    Returns (record, created).
    """
    # Match on either identity key the submission carries.
    clauses = []
    if data.isrc:
        clauses.append(TrackFacts.isrc == data.isrc)
    if data.fingerprint:
        clauses.append(TrackFacts.fingerprint == data.fingerprint)
    existing = await session.scalar(select(TrackFacts).where(or_(*clauses)))

    if existing is not None:
        # Backfill an identity key the original record was missing.
        changed = False
        if data.isrc and not existing.isrc:
            existing.isrc = data.isrc
            changed = True
        if data.fingerprint and not existing.fingerprint:
            existing.fingerprint = data.fingerprint
            changed = True
        if changed:
            await session.commit()
            await session.refresh(existing)
        return existing, False

    row = TrackFacts(
        isrc=data.isrc,
        fingerprint=data.fingerprint,
        bpm=data.bpm,
        bpm_confidence=data.bpm_confidence,
        tempo_octave_flag=data.tempo_octave_flag,
        beat_offset_ms=data.beat_offset_ms,
        energy=data.energy,
        beat_strength=data.beat_strength,
        drive_score=data.drive_score,
        duration_ms=data.duration_ms,
        analysis_version=data.analysis_version,
    )
    session.add(row)
    await session.commit()
    await session.refresh(row)
    return row, True


async def confirm(session: AsyncSession, track_id: str, data: ConfirmIn) -> TrackFacts | None:
    """Record objective feedback and, with enough independent corroboration, correct a
    low-confidence reading (Phase 6 A1). Anti-poisoning guards:
      1. one vote per (track, client, signal)  — single client can't stuff the count;
      2. override needs ≥ MIN_CORROBORATION *distinct* clients — independent corroboration;
      3. only low-confidence facts can be overridden — confident facts are never touched;
      4. corrected BPMs must cluster (agreement) — divergent/malicious values are ignored.
    """
    track = await session.get(TrackFacts, track_id)
    if track is None:
        return None

    # Guard 1: idempotent per (track, client, signal).
    exists = await session.scalar(
        select(TrackConfirmation).where(
            TrackConfirmation.track_id == track_id,
            TrackConfirmation.client_id == data.client_id,
            TrackConfirmation.signal == data.signal,
        )
    )
    if exists is None:
        session.add(TrackConfirmation(
            track_id=track_id, client_id=data.client_id,
            signal=data.signal, observed_bpm=data.observed_bpm))
        await session.flush()

    # confirmation_count = distinct clients corroborating the reading is correct.
    track.confirmation_count = await session.scalar(
        select(func.count(func.distinct(TrackConfirmation.client_id))).where(
            TrackConfirmation.track_id == track_id,
            TrackConfirmation.signal == "confirm",
        )
    ) or 0

    # Guard 3: correction only applies to low-confidence readings.
    if track.bpm_confidence < CONFIDENCE_OVERRIDE_THRESHOLD:
        rows = (await session.execute(
            select(TrackConfirmation.client_id, TrackConfirmation.observed_bpm).where(
                TrackConfirmation.track_id == track_id,
                TrackConfirmation.signal == "off_tempo",
                TrackConfirmation.observed_bpm.is_not(None),
            )
        )).all()
        by_client = {client_id: bpm for client_id, bpm in rows}   # one obs per client
        values = sorted(by_client.values())
        # Guard 2 + 4: enough independent clients AND they agree (cluster around median).
        if len(values) >= MIN_CORROBORATION:
            median = values[len(values) // 2]
            agreeing = [v for v in values if abs(v - median) <= CORRECTION_TOLERANCE]
            if len(agreeing) >= MIN_CORROBORATION:
                track.bpm = median
                track.bpm_confidence = max(track.bpm_confidence, 0.6)
                track.analysis_version = "crowd-corrected"

    await session.commit()
    await session.refresh(track)
    return track


async def coverage(session: AsyncSession, *, confident_threshold: float = 0.5) -> dict:
    """Table-wide counters for the client's coverage view and for watching the shared
    table grow. One pass of aggregates — never a full scan of rows into memory."""
    total, with_isrc, with_fp, confident, confirmed, mean_conf = (
        await session.execute(
            select(
                func.count(TrackFacts.id),
                func.count(TrackFacts.isrc),
                func.count(TrackFacts.fingerprint),
                func.sum(
                    case((TrackFacts.bpm_confidence >= confident_threshold, 1), else_=0)
                ),
                func.sum(case((TrackFacts.confirmation_count > 0, 1), else_=0)),
                func.avg(TrackFacts.bpm_confidence),
            )
        )
    ).one()

    versions = (
        await session.execute(
            select(TrackFacts.analysis_version, func.count(TrackFacts.id)).group_by(
                TrackFacts.analysis_version
            )
        )
    ).all()

    return {
        "tracks": total or 0,
        "with_isrc": with_isrc or 0,
        "with_fingerprint": with_fp or 0,
        "confident": int(confident or 0),
        "confirmed": int(confirmed or 0),
        "by_analysis_version": {version: count for version, count in versions},
        "mean_confidence": round(mean_conf, 4) if mean_conf is not None else None,
    }
