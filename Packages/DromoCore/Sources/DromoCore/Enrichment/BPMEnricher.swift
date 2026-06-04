import Foundation

/// Looks up a track's BPM by metadata (no audio, no ISRC needed) — the escape hatch
/// for DRM streaming libraries (Apple Music) that can't be analyzed on-device. Backed
/// by a 3rd-party BPM database (GetSongBPM) in the app; a protocol here so the
/// enrichment flow is testable without the network.
public protocol BPMLookup: Sendable {
    func bpm(title: String, artist: String) async -> Double?
}

/// Where enriched BPM values are persisted (on-device cache).
public protocol BPMSink: Sendable {
    func store(bpm: Double, trackID: String) async
}

/// One track that needs a BPM (identity + display metadata for the lookup).
public struct EnrichmentItem: Sendable, Equatable {
    public let trackID: String
    public let title: String
    public let artist: String
    public init(trackID: String, title: String, artist: String) {
        self.trackID = trackID
        self.title = title
        self.artist = artist
    }
}

/// Enriches a library's missing BPMs: one metadata lookup per track, rate-limited,
/// results cached. Pure orchestration (lookup + sink + delay injected) so it's
/// unit-testable; the app supplies the real GetSongBPM client + GRDB cache.
public actor BPMEnricher {

    public struct Progress: Sendable, Equatable {
        public var done: Int
        public var total: Int
        public var enriched: Int
    }

    private let lookup: BPMLookup
    private let sink: BPMSink
    /// Free-tier rate limit (~1 req/sec). 0 in tests.
    private let minIntervalNanos: UInt64

    public init(lookup: BPMLookup, sink: BPMSink, minIntervalNanos: UInt64 = 1_100_000_000) {
        self.lookup = lookup
        self.sink = sink
        self.minIntervalNanos = minIntervalNanos
    }

    /// Looks up + caches BPM for each item, reporting progress. Returns the count
    /// successfully enriched. Cancellation-aware (stops if the Task is cancelled).
    @discardableResult
    public func enrich(_ items: [EnrichmentItem],
                       onProgress: (@Sendable (Progress) -> Void)? = nil) async -> Int {
        var enriched = 0
        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }

            if let bpm = await lookup.bpm(title: item.title, artist: item.artist), bpm > 60 {
                await sink.store(bpm: bpm, trackID: item.trackID)
                enriched += 1
            }
            onProgress?(Progress(done: index + 1, total: items.count, enriched: enriched))

            if minIntervalNanos > 0, index < items.count - 1 {
                try? await Task.sleep(nanoseconds: minIntervalNanos)
            }
        }
        return enriched
    }
}
