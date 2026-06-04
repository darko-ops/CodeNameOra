import Foundation
import DromoCore

/// App-side configuration + factory that assembles the Phase-3 sync stack:
/// HTTP client → Global Track Table, GRDB local cache, and on-device analysis.
enum LibrarySync {

    /// Server base URL. Overridable via the `DROMO_API` env var for dev/staging.
    static var baseURL: URL {
        if let raw = ProcessInfo.processInfo.environment["DROMO_API"], let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://localhost:8000")!
    }

    /// Builds a coordinator wired to the real client, cache, and analyzer.
    /// `urlForItem` maps a library item back to its analyzable file URL (e.g. an
    /// `MPMediaItem.assetURL`); the live library flow provides it in Phase 5.
    static func makeCoordinator(
        urlForItem: @escaping @Sendable (SyncItem) -> URL?
    ) -> LibrarySyncCoordinator {
        let analyzer = TrackAnalyzer()
        return LibrarySyncCoordinator(
            api: HTTPTrackTableClient(baseURL: baseURL),
            cache: GRDBTrackFactsCache()
        ) { item in
            guard let url = urlForItem(item) else { return nil }
            return await analyzer.analyze(url: url)?.result
        }
    }
}
