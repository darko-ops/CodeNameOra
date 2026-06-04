"""Global Track Table ORM (ARCHITECTURE §7 schema).

FACTS ONLY. No audio, ever. No titles/artists either — those stay on-device as
labels (ARCHITECTURE §5 separation + Phase 3 privacy). Identity is ISRC or
acoustic fingerprint, nothing personally identifying.
"""
from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy import CheckConstraint, DateTime, Float, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


def _uuid() -> str:
    return uuid4().hex


def _now() -> datetime:
    return datetime.now(timezone.utc)


class TrackFacts(Base):
    __tablename__ = "track_facts"
    __table_args__ = (
        # At least one identity key must be present (ARCHITECTURE §6).
        CheckConstraint(
            "isrc IS NOT NULL OR fingerprint IS NOT NULL",
            name="ck_track_identity_present",
        ),
    )

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)

    # --- Identity (§6) ---
    isrc: Mapped[str | None] = mapped_column(String(15), unique=True, index=True)
    fingerprint: Mapped[str | None] = mapped_column(String, unique=True, index=True)

    # --- Tier 1: essential (§7) ---
    bpm: Mapped[float] = mapped_column(Float)
    bpm_confidence: Mapped[float] = mapped_column(Float)
    # half/double-time ambiguity marker: 'none' | 'half' | 'double' | 'ambiguous'
    tempo_octave_flag: Mapped[str] = mapped_column(String(10), default="none")
    beat_offset_ms: Mapped[int | None] = mapped_column(Integer)

    # --- Tier 2: high value for pacing (§7) ---
    energy: Mapped[float | None] = mapped_column(Float)
    beat_strength: Mapped[float | None] = mapped_column(Float)
    drive_score: Mapped[float | None] = mapped_column(Float)

    # --- Tier 3 (cheap, useful now) ---
    duration_ms: Mapped[int | None] = mapped_column(Integer)

    # --- Bookkeeping (§7) ---
    analysis_version: Mapped[str] = mapped_column(String(32))
    confirmation_count: Mapped[int] = mapped_column(Integer, default=0)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_now, onupdate=_now
    )


class TrackConfirmation(Base):
    """Objective feedback toward the *global* facts (Phase 6 / §8 A1).

    One row per (track, client, signal) — the UNIQUE constraint is the first
    anti-poisoning guard: a single client cannot stuff the count. Subjective taste
    NEVER lands here (that's the private per-user layer, ARCHITECTURE §5/§8 A2).
    """
    __tablename__ = "track_confirmations"
    __table_args__ = (
        UniqueConstraint("track_id", "client_id", "signal", name="uq_confirmation"),
    )

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    track_id: Mapped[str] = mapped_column(String(32), index=True)
    client_id: Mapped[str] = mapped_column(String(64), index=True)
    signal: Mapped[str] = mapped_column(String(16))   # 'confirm' | 'off_tempo'
    observed_bpm: Mapped[float | None] = mapped_column(Float)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
