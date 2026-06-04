import XCTest
@testable import DromoCore

private final class FakePlayback: PlaybackControlling, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var played: [String] = []
    var failIDs: Set<String> = []

    func play(trackID: String) async -> Bool {
        lock.lock(); defer { lock.unlock() }
        if failIDs.contains(trackID) { return false }
        played.append(trackID)
        return true
    }
}

final class LiveLoopTests: XCTestCase {

    private func facts(_ id: String, bpm: Double, energy: Double = 0.5) -> TrackFacts {
        TrackFacts(id: id, bpm: bpm, bpmConfidence: 0.9, tempoOctaveFlag: .none,
                   energy: energy, beatStrength: 0.6, analysisVersion: "vdsp-1")
    }

    // MARK: Target derivation (three input modes)

    func testTargetDerivations() {
        XCTAssertEqual(PaceTarget.fromPacePerKm(minutes: 5, seconds: 0), 300, accuracy: 0.001)
        XCTAssertEqual(PaceTarget.fromPacePerMile(minutes: 8, seconds: 0), 298.26, accuracy: 0.5)
        XCTAssertEqual(PaceTarget.fromGoalTime(distanceMeters: 10_000, goalSeconds: 3_000),
                       300, accuracy: 0.001)
    }

    func testCadenceModelRisesWithSpeed() {
        let m = CadenceModel()
        XCTAssertGreaterThan(m.targetCadence(forPaceSecPerKm: 240),   // faster
                             m.targetCadence(forPaceSecPerKm: 360))   // slower
    }

    func testSmootherRejectsGarbageAndConverges() {
        var s = CadenceSmoother()
        _ = s.add(170)
        _ = s.add(9_999)                 // implausible → ignored
        let v = s.add(170)
        XCTAssertEqual(v, 170, accuracy: 1)
    }

    // MARK: The live loop

    func testStartPlaysFirstTrack() async {
        let pb = FakePlayback()
        let loop = LiveLoop(playback: pb, candidates: [facts("a", bpm: 170)],
                            targetPaceSecPerKm: 300)
        let state = await loop.start()
        XCTAssertEqual(state.nowPlayingTrackID, "a")
        XCTAssertEqual(pb.played, ["a"])
    }

    func testIngestUpdatesNudgeButNotTrack() async {
        let pb = FakePlayback()
        let loop = LiveLoop(playback: pb, candidates: [facts("a", bpm: 170), facts("b", bpm: 180)],
                            targetPaceSecPerKm: 300)   // target cadence 170
        _ = await loop.start()
        // Cadence far below target ⇒ behind ⇒ speed up; no new track played on ingest.
        let state = await loop.ingest(rawCadence: 150, paceSecPerKm: 330)
        XCTAssertEqual(state.nudge, .speedUp)
        XCTAssertEqual(pb.played.count, 1, "ingest must not switch tracks")
    }

    func testHandsFreeAdvanceOnTrackEnd() async {
        let pb = FakePlayback()
        let loop = LiveLoop(playback: pb,
                            candidates: [facts("a", bpm: 168), facts("b", bpm: 170), facts("c", bpm: 172)],
                            targetPaceSecPerKm: 300)
        _ = await loop.start()
        _ = await loop.trackDidEnd()
        _ = await loop.trackDidEnd()
        // Three boundary events → three distinct tracks, zero manual track control.
        XCTAssertEqual(pb.played.count, 3)
        XCTAssertEqual(Set(pb.played).count, 3)
    }

    func testGracefullySkipsUnavailableTrack() async {
        let pb = FakePlayback()
        pb.failIDs = ["broken"]
        let loop = LiveLoop(playback: pb,
                            candidates: [facts("broken", bpm: 170), facts("good", bpm: 169)],
                            targetPaceSecPerKm: 300)
        let state = await loop.start()
        XCTAssertEqual(state.nowPlayingTrackID, "good", "skips the unplayable track")
        XCTAssertFalse(pb.played.contains("broken"))
    }

    func testEmptyPoolDoesNotCrash() async {
        let pb = FakePlayback()
        let loop = LiveLoop(playback: pb, candidates: [], targetPaceSecPerKm: 300)
        let state = await loop.start()
        XCTAssertNil(state.nowPlayingTrackID)
        XCTAssertTrue(pb.played.isEmpty)
    }

    func testUpdateCandidatesSwapsPoolMidSession() async {
        let pb = FakePlayback()
        let loop = LiveLoop(playback: pb, candidates: [facts("a", bpm: 170)],
                            targetPaceSecPerKm: 300)
        _ = await loop.start()                          // plays "a"
        await loop.updateCandidates([facts("b", bpm: 170)])
        _ = await loop.trackDidEnd()                    // pool now only "b"
        XCTAssertEqual(pb.played.last, "b")
    }

    func testUpdatePreferencesSteersSelection() async {
        let pb = FakePlayback()
        let loop = LiveLoop(playback: pb,
                            candidates: [facts("plain", bpm: 170), facts("loved", bpm: 170)],
                            targetPaceSecPerKm: 300)
        await loop.updatePreferences(["loved": 1.0])
        let state = await loop.start()
        XCTAssertEqual(state.nowPlayingTrackID, "loved")
    }

    func testFullHandsFreeRun() async {
        let pb = FakePlayback()
        let pool = (0..<8).map { facts("t\($0)", bpm: 168 + Double($0)) }
        let loop = LiveLoop(playback: pb, candidates: pool, targetPaceSecPerKm: 300)
        _ = await loop.start()
        // Simulate a run: sensor ticks interleaved with track-end boundaries.
        for i in 0..<6 {
            _ = await loop.ingest(rawCadence: 160 + Double(i), paceSecPerKm: 315)
            _ = await loop.trackDidEnd()
        }
        XCTAssertEqual(pb.played.count, 7, "1 start + 6 boundaries, all hands-free")
    }
}
