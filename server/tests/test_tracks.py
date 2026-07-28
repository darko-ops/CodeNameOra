"""Phase 1 acceptance: lookup + populate, identity, idempotency, legal boundary."""
from __future__ import annotations

import pytest

pytestmark = pytest.mark.asyncio


def _facts(**overrides) -> dict:
    base = {
        "isrc": "USRC17607839",
        "bpm": 174.0,
        "bpm_confidence": 0.92,
        "tempo_octave_flag": "none",
        "energy": 0.8,
        "beat_strength": 0.7,
        "drive_score": 0.77,
        "duration_ms": 210000,
        "analysis_version": "vdsp-1",
    }
    base.update(overrides)
    return base


async def test_health(client):
    r = await client.get("/healthz")
    assert r.status_code == 200 and r.json()["status"] == "ok"


async def test_populate_then_lookup_by_isrc(client):
    r = await client.post("/v1/track", json=_facts())
    assert r.status_code == 201
    body = r.json()
    assert body["created"] is True
    assert body["track"]["bpm"] == 174.0
    assert body["track"]["confirmation_count"] == 0

    r = await client.get("/v1/track", params={"isrc": "USRC17607839"})
    assert r.status_code == 200
    assert r.json()["isrc"] == "USRC17607839"


async def test_lookup_by_fingerprint(client):
    await client.post(
        "/v1/track", json=_facts(isrc=None, fingerprint="AQADtMmYkYkkk", bpm=128.0)
    )
    r = await client.get("/v1/track", params={"fingerprint": "AQADtMmYkYkkk"})
    assert r.status_code == 200 and r.json()["bpm"] == 128.0


async def test_lookup_miss_returns_404(client):
    r = await client.get("/v1/track", params={"isrc": "NOPE00000000"})
    assert r.status_code == 404


async def test_lookup_requires_a_key(client):
    r = await client.get("/v1/track")
    assert r.status_code == 400


async def test_identity_required_on_populate(client):
    r = await client.post("/v1/track", json=_facts(isrc=None, fingerprint=None))
    assert r.status_code == 422  # validator: at least one of isrc/fingerprint


async def test_audio_payload_is_rejected(client):
    # ARCHITECTURE §4: extra="forbid" blocks any attempt to smuggle audio.
    r = await client.post(
        "/v1/track", json=_facts(audio_samples=[0.1, 0.2, 0.3])
    )
    assert r.status_code == 422


async def test_populate_is_idempotent_first_write_wins(client):
    await client.post("/v1/track", json=_facts(bpm=174.0))
    # Second device submits a different reading for the SAME recording.
    r = await client.post("/v1/track", json=_facts(bpm=87.0, bpm_confidence=0.4))
    assert r.status_code == 200
    body = r.json()
    assert body["created"] is False
    assert body["track"]["bpm"] == 174.0  # original facts preserved


async def test_two_devices_same_isrc_second_gets_hit(client):
    # The whole point of analyze-once-globally (ARCHITECTURE §6).
    r1 = await client.post("/v1/track", json=_facts())
    assert r1.json()["created"] is True
    r2 = await client.get("/v1/track", params={"isrc": "USRC17607839"})
    assert r2.status_code == 200  # second device never analyzed; it looked up


async def test_populate_backfills_missing_fingerprint(client):
    # First record has only an ISRC; a later submission adds the fingerprint.
    await client.post("/v1/track", json=_facts(fingerprint=None))
    r = await client.post(
        "/v1/track", json=_facts(fingerprint="AQADfound", bpm=120.0)
    )
    assert r.json()["created"] is False
    assert r.json()["track"]["fingerprint"] == "AQADfound"
    # facts still first-write-wins
    assert r.json()["track"]["bpm"] == 174.0


async def test_batch_lookup_mixed_hits_and_misses(client):
    await client.post("/v1/track", json=_facts(isrc="HIT0000000001"))
    body = {
        "keys": [
            {"isrc": "HIT0000000001"},
            {"isrc": "MISS000000002"},
            {"fingerprint": "alsomiss"},
        ]
    }
    r = await client.post("/v1/track/batch", json=body)
    assert r.status_code == 200
    results = r.json()["results"]
    assert [x["hit"] for x in results] == [True, False, False]
    assert results[0]["track"]["isrc"] == "HIT0000000001"


async def test_bpm_range_validation(client):
    r = await client.post("/v1/track", json=_facts(bpm=-5))
    assert r.status_code == 422
    r = await client.post("/v1/track", json=_facts(bpm_confidence=1.5))
    assert r.status_code == 422


# --- Coverage counters (Phase 2 telemetry) ----------------------------------


async def test_coverage_starts_empty(client):
    """An empty table reports zeros, not nulls — the client renders this directly."""
    r = await client.get("/v1/track/coverage")
    assert r.status_code == 200
    body = r.json()
    assert body["tracks"] == 0
    assert body["confident"] == 0
    assert body["by_analysis_version"] == {}
    assert body["mean_confidence"] is None


async def test_coverage_counts_identity_confidence_and_versions(client):
    await client.post("/v1/track", json=_facts(isrc="USRC17607839", bpm_confidence=0.92))
    await client.post(
        "/v1/track",
        json=_facts(
            isrc=None,
            fingerprint="chroma-abc",
            bpm_confidence=0.3,
            analysis_version="vdsp-2",
        ),
    )

    body = (await client.get("/v1/track/coverage")).json()

    assert body["tracks"] == 2
    assert body["with_isrc"] == 1
    assert body["with_fingerprint"] == 1
    # Only the 0.92 reading clears the confidence bar; the 0.3 one is a guess.
    assert body["confident"] == 1
    assert body["by_analysis_version"] == {"vdsp-1": 1, "vdsp-2": 1}
    assert body["mean_confidence"] == pytest.approx(0.61, abs=0.01)


async def test_coverage_counts_confirmed_recordings(client):
    created = await client.post("/v1/track", json=_facts())
    track_id = created.json()["track"]["id"]

    assert (await client.get("/v1/track/coverage")).json()["confirmed"] == 0

    await client.post(
        f"/v1/track/{track_id}/confirm",
        json={"signal": "confirm", "client_id": "device-a"},
    )

    assert (await client.get("/v1/track/coverage")).json()["confirmed"] == 1
