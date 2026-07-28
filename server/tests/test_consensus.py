"""Phase 4 consensus: several devices analyzing the same recording.

First-write-wins protects the table from churn when everyone agrees, but on its own
it freezes a wrong first reading forever. These pin the rule that replaced it:
independent agreement can correct the stored value; a lone dissenter cannot.
"""
from __future__ import annotations

import pytest

from app.crud import consensus


def _facts(**overrides) -> dict:
    base = {
        "isrc": "USRC17607839",
        "bpm": 174.0,
        "bpm_confidence": 0.9,
        "tempo_octave_flag": "none",
        "analysis_version": "vdsp-1",
        "client_id": "device-a",
    }
    base.update(overrides)
    return base


# --- the pure rule ----------------------------------------------------------


def test_consensus_weights_confidence_not_headcount():
    # Three hesitant guesses at 120 vs two firm readings at 174: confidence decides,
    # because counting heads would let uncertainty outvote measurement.
    submissions = [
        ("a", 120.0, 0.2), ("b", 120.5, 0.2), ("c", 119.5, 0.2),
        ("d", 174.0, 0.95), ("e", 174.2, 0.93),
    ]
    bpm, confidence, outliers = consensus(submissions)

    assert bpm == pytest.approx(174.1, abs=0.2)
    assert outliers == {"a", "b", "c"}
    assert confidence > 0.95


def test_half_tempo_reading_is_rejected_not_averaged():
    # The failure a plain mean would produce: 87 and 174 averaging to 130, a tempo
    # nobody measured and no runner could run to.
    bpm, _, outliers = consensus([("a", 174.0, 0.9), ("b", 174.5, 0.9), ("c", 87.0, 0.8)])

    assert bpm == pytest.approx(174.25, abs=0.2)
    assert outliers == {"c"}


def test_agreement_raises_confidence_but_never_to_certainty():
    _, one, _ = consensus([("a", 174.0, 0.9)])
    _, three, _ = consensus([("a", 174.0, 0.9), ("b", 174.0, 0.9), ("c", 174.0, 0.9)])

    assert three > one
    assert three <= 0.99


def test_empty_submissions_are_not_a_reading():
    assert consensus([]) == (0.0, 0.0, set())


# --- through the API --------------------------------------------------------


@pytest.mark.asyncio
async def test_second_device_agreeing_raises_confidence(client):
    created = await client.post("/v1/track", json=_facts(bpm_confidence=0.8))
    assert created.json()["created"] is True

    await client.post("/v1/track", json=_facts(client_id="device-b", bpm=174.4,
                                               bpm_confidence=0.8))

    facts = (await client.get("/v1/track", params={"isrc": "USRC17607839"})).json()
    assert facts["bpm"] == pytest.approx(174.0, abs=0.5)
    assert facts["bpm_confidence"] > 0.8, "independent corroboration is evidence"


@pytest.mark.asyncio
async def test_lone_dissenter_cannot_move_the_stored_tempo(client):
    await client.post("/v1/track", json=_facts())
    await client.post("/v1/track", json=_facts(client_id="device-b", bpm=87.0,
                                               bpm_confidence=0.99))

    facts = (await client.get("/v1/track", params={"isrc": "USRC17607839"})).json()
    assert facts["bpm"] == pytest.approx(174.0, abs=0.5), "one disagreement is not consensus"


@pytest.mark.asyncio
async def test_two_agreeing_devices_correct_a_wrong_first_reading(client):
    # The case first-write-wins could never fix.
    await client.post("/v1/track", json=_facts(bpm=87.0, bpm_confidence=0.55))
    await client.post("/v1/track", json=_facts(client_id="device-b", bpm=174.0,
                                               bpm_confidence=0.95))
    await client.post("/v1/track", json=_facts(client_id="device-c", bpm=174.3,
                                               bpm_confidence=0.93))

    facts = (await client.get("/v1/track", params={"isrc": "USRC17607839"})).json()
    assert facts["bpm"] == pytest.approx(174.15, abs=0.5)


@pytest.mark.asyncio
async def test_one_device_cannot_outvote_the_crowd_by_resubmitting(client):
    await client.post("/v1/track", json=_facts())
    for _ in range(5):
        await client.post("/v1/track", json=_facts(client_id="device-b", bpm=87.0,
                                                   bpm_confidence=0.99))

    facts = (await client.get("/v1/track", params={"isrc": "USRC17607839"})).json()
    assert facts["bpm"] == pytest.approx(174.0, abs=0.5), "one row per device, per version"


@pytest.mark.asyncio
async def test_submission_without_a_client_id_is_stored_but_does_not_vote(client):
    # Backward compatibility: an older client can still populate a miss.
    created = await client.post("/v1/track", json=_facts(client_id=None))
    assert created.status_code == 201
    assert created.json()["track"]["bpm"] == pytest.approx(174.0)
