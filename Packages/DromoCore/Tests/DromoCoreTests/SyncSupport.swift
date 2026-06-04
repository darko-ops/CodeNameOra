import Foundation
@testable import DromoCore

/// A fake Global Track Table shared across "devices" in a test — first-write-wins,
/// with call counters so tests can prove what crossed the network.
final class FakeTrackTable: TrackTableAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var byISRC: [String: TrackFacts] = [:]
    private var byFP: [String: TrackFacts] = [:]
    private var seq = 0

    private(set) var lookupCalls = 0
    private(set) var batchCalls = 0
    private(set) var populateCalls = 0
    private(set) var confirmCalls = 0
    private var byID: [String: TrackFacts] = [:]
    /// Captures every payload uploaded, so a test can assert no titles/audio leak.
    private(set) var uploaded: [AnalysisResult] = []

    func lookup(_ key: IdentityKey) async throws -> TrackFacts? {
        lock.lock(); defer { lock.unlock() }
        lookupCalls += 1
        return find(key)
    }

    func batchLookup(_ keys: [IdentityKey]) async throws -> [BatchResult] {
        lock.lock(); defer { lock.unlock() }
        batchCalls += 1
        return keys.map { BatchResult(key: $0, facts: find($0)) }
    }

    func populate(_ result: AnalysisResult) async throws -> TrackFacts {
        lock.lock(); defer { lock.unlock() }
        populateCalls += 1
        uploaded.append(result)
        if let existing = find(IdentityKey(isrc: result.isrc, fingerprint: result.fingerprint)) {
            return existing   // first-write-wins
        }
        seq += 1
        let facts = TrackFacts(
            id: "srv-\(seq)", isrc: result.isrc, fingerprint: result.fingerprint,
            bpm: result.bpm, bpmConfidence: result.bpmConfidence,
            tempoOctaveFlag: result.tempoOctaveFlag, beatOffsetMs: result.beatOffsetMs,
            energy: result.energy, beatStrength: result.beatStrength,
            driveScore: result.driveScore, durationMs: result.durationMs,
            analysisVersion: result.analysisVersion, confirmationCount: 0)
        store(facts)
        return facts
    }

    func confirm(trackID: String, signal: ObjectiveSignal, clientID: String) async throws -> TrackFacts? {
        lock.lock(); defer { lock.unlock() }
        confirmCalls += 1
        guard var facts = byID[trackID] else { return nil }
        if signal.serverSignal == "confirm" { facts.confirmationCount += 1 }
        byID[trackID] = facts
        return facts
    }

    /// Seed the server as if another device already populated it.
    func seed(_ facts: TrackFacts) {
        lock.lock(); defer { lock.unlock() }
        store(facts)
    }

    private func store(_ facts: TrackFacts) {
        if let i = facts.isrc { byISRC[i] = facts }
        if let f = facts.fingerprint { byFP[f] = facts }
        byID[facts.id] = facts
    }

    private func find(_ key: IdentityKey) -> TrackFacts? {
        if let i = key.isrc, let f = byISRC[i] { return f }
        if let fp = key.fingerprint, let f = byFP[fp] { return f }
        return nil
    }
}

/// Thread-safe call counter — safe to capture in a `@Sendable` analyze closure.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    func inc() { lock.lock(); n += 1; lock.unlock() }
}

func stubAnalysis(isrc: String? = nil, fingerprint: String? = nil, bpm: Double = 150) -> AnalysisResult {
    AnalysisResult(isrc: isrc, fingerprint: fingerprint, bpm: bpm, bpmConfidence: 0.9,
                   tempoOctaveFlag: .none, energy: 0.6, beatStrength: 0.6, driveScore: 0.6,
                   durationMs: 200_000, analysisVersion: "vdsp-1")
}
