import Foundation

/// Where a BPM came from. Attribution travels WITH the number for two reasons: a
/// stronger source must be able to overwrite a weaker one on a later pass, and a
/// tempo we half-trust should not present itself like one we measured.
///
/// The order is the enrichment chain's order, cheapest and most trustworthy first
/// (ARCHITECTURE §6 lookup-first):
///   1. the Global Track Table — someone already analyzed this recording,
///   2. the platform's own tag — free, already on the device,
///   3. GetSongBPM — a metadata database, one HTTP call,
///   4. Spotify audio-features — LAST: restricted for new apps and deprecation-prone.
public enum BPMSource: String, Sendable, Codable, CaseIterable {
    case trackTable
    case provider
    case getSongBPM
    case spotify

    /// Higher wins when two sources disagree about the same recording.
    public var trust: Int {
        switch self {
        case .trackTable: return 4     // measured from audio, corroborated across users
        case .provider:   return 3     // the rights-holder's own tag
        case .getSongBPM: return 2     // community database
        case .spotify:    return 1     // opaque, restricted, may vanish
        }
    }

    /// Confidence to record alongside the value. Only the Track Table clears
    /// `SelectionConfig.confidenceThreshold` comfortably; the rest are usable but
    /// discounted, which is exactly how `LibraryCoverage` should count them.
    public var confidence: Double {
        switch self {
        case .trackTable: return 0.9
        case .provider:   return 0.7
        case .getSongBPM: return 0.6
        case .spotify:    return 0.55
        }
    }

    /// Does this source need the network? Governs the cellular/battery gate.
    public var needsNetwork: Bool { self != .provider }
}

/// A BPM with its provenance — what gets cached, so a later pass can tell whether a
/// new reading is an upgrade or a downgrade.
public struct BPMFinding: Sendable, Equatable, Codable {
    public let bpm: Double
    public let source: BPMSource
    public let confidence: Double

    public init(bpm: Double, source: BPMSource, confidence: Double? = nil) {
        self.bpm = bpm
        self.source = source
        self.confidence = confidence ?? source.confidence
    }

    /// Should `self` replace `existing`? Only a more-trusted source may overwrite;
    /// equal trust keeps what's already cached (no churn from re-running a pass).
    public func supersedes(_ existing: BPMFinding?) -> Bool {
        guard let existing else { return true }
        return source.trust > existing.source.trust
    }
}

/// One link in the enrichment chain. Throwing is meaningful: a THROW is "this source
/// is unhappy" (rate limit, network) and feeds backoff, while returning nil is simply
/// "no data for this track" and moves to the next source.
public protocol BPMSourcing: Sendable {
    var source: BPMSource { get }
    func bpm(for item: EnrichmentItem) async throws -> Double?
}

/// Tries sources in order and returns the first hit, tagged with its origin.
///
/// Replaces the untagged `ChainedBPMLookup` for the background pass: same
/// short-circuit behaviour, but the caller learns WHICH source answered, and a
/// failing source degrades the chain instead of ending it.
public struct BPMSourceChain: Sendable {

    public struct Outcome: Sendable, Equatable {
        public var finding: BPMFinding?
        /// Sources that errored on this item — the signal that drives backoff.
        public var failedSources: [BPMSource] = []
        public var isTransientFailure: Bool { finding == nil && !failedSources.isEmpty }
    }

    private let sources: [BPMSourcing]
    /// A tempo below this is a metadata artefact (half-time tags, zero, junk).
    private let minPlausibleBPM: Double

    public init(_ sources: [BPMSourcing], minPlausibleBPM: Double = 60) {
        // Order is policy, not caller discipline: sort by trust so a mis-ordered
        // wiring can't quietly put Spotify ahead of the Track Table.
        self.sources = sources.sorted { $0.source.trust > $1.source.trust }
        self.minPlausibleBPM = minPlausibleBPM
    }

    public var order: [BPMSource] { sources.map(\.source) }

    public func find(for item: EnrichmentItem) async -> Outcome {
        var outcome = Outcome()
        for source in sources {
            if Task.isCancelled { return outcome }
            do {
                guard let bpm = try await source.bpm(for: item), bpm >= minPlausibleBPM else {
                    continue                                   // no data here — try the next
                }
                outcome.finding = BPMFinding(bpm: bpm, source: source.source)
                return outcome
            } catch {
                outcome.failedSources.append(source.source)    // unhappy — remember, keep going
            }
        }
        return outcome
    }
}

/// Adapts a legacy title/artist `BPMLookup` into the attributed chain.
public struct LegacyBPMSource: BPMSourcing {
    public let source: BPMSource
    private let lookup: BPMLookup

    public init(source: BPMSource, lookup: BPMLookup) {
        self.source = source
        self.lookup = lookup
    }

    public func bpm(for item: EnrichmentItem) async throws -> Double? {
        await lookup.bpm(title: item.title, artist: item.artist)
    }
}

/// The tempo the platform already handed us (`MPMediaItem.beatsPerMinute`). Free,
/// offline, and second only to the Track Table — so it must be consulted before any
/// HTTP call, not after.
public struct ProviderTagSource: BPMSourcing {
    public let source = BPMSource.provider
    public init() {}
    public func bpm(for item: EnrichmentItem) async throws -> Double? { item.providerBPM }
}
