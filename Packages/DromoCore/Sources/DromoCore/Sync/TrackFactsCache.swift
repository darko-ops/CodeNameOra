import Foundation

/// On-device cache of resolved facts so repeat sessions need no network
/// (ARCHITECTURE / Phase 3 local cache). The app backs this with GRDB; tests use
/// the in-memory implementation below.
public protocol TrackFactsCache: Sendable {
    func get(_ key: IdentityKey) async -> TrackFacts?
    func put(_ facts: TrackFacts) async
    func all() async -> [TrackFacts]
}

public actor InMemoryTrackFactsCache: TrackFactsCache {
    private var byISRC: [String: TrackFacts] = [:]
    private var byFingerprint: [String: TrackFacts] = [:]

    public init() {}

    public func get(_ key: IdentityKey) -> TrackFacts? {
        if let isrc = key.isrc, let f = byISRC[isrc] { return f }
        if let fp = key.fingerprint, let f = byFingerprint[fp] { return f }
        return nil
    }

    public func put(_ facts: TrackFacts) {
        if let isrc = facts.isrc { byISRC[isrc] = facts }
        if let fp = facts.fingerprint { byFingerprint[fp] = facts }
    }

    public func all() -> [TrackFacts] {
        var seen = Set<String>()
        var out: [TrackFacts] = []
        for f in Array(byISRC.values) + Array(byFingerprint.values) where seen.insert(f.id).inserted {
            out.append(f)
        }
        return out
    }
}
