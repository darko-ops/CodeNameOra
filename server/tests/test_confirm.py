"""Phase 6 A1: objective confirm/correction with anti-poisoning guards."""
from __future__ import annotations

import pytest

pytestmark = pytest.mark.asyncio


async def _make_track(client, *, isrc="USRC00000777", bpm=170.0, confidence=0.9) -> str:
    r = await client.post("/v1/track", json={
        "isrc": isrc, "bpm": bpm, "bpm_confidence": confidence, "analysis_version": "vdsp-1"})
    return r.json()["track"]["id"]


async def test_confirm_counts_distinct_clients(client):
    tid = await _make_track(client)
    await client.post(f"/v1/track/{tid}/confirm", json={"client_id": "a", "signal": "confirm"})
    await client.post(f"/v1/track/{tid}/confirm", json={"client_id": "a", "signal": "confirm"})  # dup
    r = await client.post(f"/v1/track/{tid}/confirm", json={"client_id": "b", "signal": "confirm"})
    assert r.status_code == 200
    assert r.json()["confirmation_count"] == 2   # a (once) + b, not 3


async def test_low_confidence_corrected_after_corroboration(client):
    tid = await _make_track(client, bpm=170, confidence=0.3)   # low confidence
    for c in ["a", "b", "c"]:
        await client.post(f"/v1/track/{tid}/confirm",
                          json={"client_id": c, "signal": "off_tempo", "observed_bpm": 87.0})
    r = await client.get("/v1/track", params={"isrc": "USRC00000777"})
    body = r.json()
    assert body["bpm"] == 87.0
    assert body["analysis_version"] == "crowd-corrected"


async def test_high_confidence_never_overridden(client):
    tid = await _make_track(client, bpm=170, confidence=0.95)   # confident
    for c in ["a", "b", "c", "d"]:
        await client.post(f"/v1/track/{tid}/confirm",
                          json={"client_id": c, "signal": "off_tempo", "observed_bpm": 87.0})
    r = await client.get("/v1/track", params={"isrc": "USRC00000777"})
    assert r.json()["bpm"] == 170.0   # untouched — guard 3


async def test_correction_needs_enough_independent_clients(client):
    tid = await _make_track(client, bpm=170, confidence=0.3)
    for c in ["a", "b"]:   # only 2 < MIN_CORROBORATION
        await client.post(f"/v1/track/{tid}/confirm",
                          json={"client_id": c, "signal": "off_tempo", "observed_bpm": 87.0})
    r = await client.get("/v1/track", params={"isrc": "USRC00000777"})
    assert r.json()["bpm"] == 170.0   # not enough corroboration


async def test_divergent_observations_do_not_correct(client):
    tid = await _make_track(client, bpm=170, confidence=0.3)
    for c, v in [("a", 80.0), ("b", 120.0), ("c", 175.0)]:   # no agreement
        await client.post(f"/v1/track/{tid}/confirm",
                          json={"client_id": c, "signal": "off_tempo", "observed_bpm": v})
    r = await client.get("/v1/track", params={"isrc": "USRC00000777"})
    assert r.json()["bpm"] == 170.0   # divergent → no override (guard 4)


async def test_subjective_field_is_rejected(client):
    tid = await _make_track(client)
    # Taste data must never reach the global table.
    r = await client.post(f"/v1/track/{tid}/confirm",
                          json={"client_id": "a", "signal": "confirm", "mood": "happy"})
    assert r.status_code == 422


async def test_confirm_unknown_track_404(client):
    r = await client.post("/v1/track/nope/confirm", json={"client_id": "a", "signal": "confirm"})
    assert r.status_code == 404
