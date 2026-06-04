"""Pydantic request/response models.

`extra="forbid"` is a legal-boundary guard (ARCHITECTURE §4): any unexpected
field — notably an attempt to smuggle audio/sample data — is rejected with 422.
"""
from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

OctaveFlag = Literal["none", "half", "double", "ambiguous"]


class IdentityKey(BaseModel):
    """ISRC primary, fingerprint fallback — at least one required (§6)."""

    model_config = ConfigDict(extra="forbid")

    isrc: str | None = Field(default=None, max_length=15)
    fingerprint: str | None = None

    @model_validator(mode="after")
    def _at_least_one(self) -> "IdentityKey":
        if not self.isrc and not self.fingerprint:
            raise ValueError("at least one of isrc or fingerprint is required")
        return self


class TrackFactsIn(IdentityKey):
    """Analysis result uploaded by a device on a lookup MISS (§7)."""

    # Tier 1 — essential
    bpm: float = Field(gt=0, lt=400)
    bpm_confidence: float = Field(ge=0, le=1)
    tempo_octave_flag: OctaveFlag = "none"
    beat_offset_ms: int | None = Field(default=None, ge=0)

    # Tier 2 — pacing value
    energy: float | None = Field(default=None, ge=0, le=1)
    beat_strength: float | None = Field(default=None, ge=0, le=1)
    drive_score: float | None = Field(default=None, ge=0, le=1)

    # Tier 3
    duration_ms: int | None = Field(default=None, ge=0)

    # Bookkeeping
    analysis_version: str = Field(max_length=32)


class TrackFactsOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    isrc: str | None
    fingerprint: str | None
    bpm: float
    bpm_confidence: float
    tempo_octave_flag: str
    beat_offset_ms: int | None
    energy: float | None
    beat_strength: float | None
    drive_score: float | None
    duration_ms: int | None
    analysis_version: str
    confirmation_count: int
    created_at: datetime
    updated_at: datetime


class PopulateResponse(BaseModel):
    """Whether this POST created a new global fact or matched an existing one."""

    created: bool
    track: TrackFactsOut


class ConfirmIn(BaseModel):
    """Objective feedback on a recording's facts (Phase 6 A1). `extra="forbid"`
    means no subjective/taste field can ride along to the global table (§5 boundary)."""

    model_config = ConfigDict(extra="forbid")

    client_id: str = Field(min_length=1, max_length=64)
    signal: Literal["confirm", "off_tempo"]
    observed_bpm: float | None = Field(default=None, gt=0, lt=400)


class BatchLookupIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    keys: list[IdentityKey] = Field(min_length=1, max_length=500)


class BatchLookupItem(BaseModel):
    key: IdentityKey
    hit: bool
    track: TrackFactsOut | None = None


class BatchLookupResponse(BaseModel):
    results: list[BatchLookupItem]
