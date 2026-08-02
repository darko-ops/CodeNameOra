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

    /// Whether the Global Track Table is actually reachable from where the app is
    /// running. The default base URL is localhost, which on a phone is the phone — so an
    /// unset `DROMO_API` means there is no track table to ask, not merely a slow one.
    /// Treating it as a live source is what let a build with no tempo source at all look
    /// like one that was simply still working.
    static var isConfigured: Bool {
        guard let host = baseURL.host else { return false }
        return !["localhost", "127.0.0.1", "::1"].contains(host)
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
