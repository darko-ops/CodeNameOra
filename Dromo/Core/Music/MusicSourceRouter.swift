import Foundation
import DromoCore

/// One `MusicProviderProtocol` face over every connected service.
///
/// The unified library means a session's tracks can come from different apps, but
/// playback, catalog-ISRC identity, and analyzable-URL resolution are all per-service
/// calls. This router owns the track → service mapping so every existing consumer
/// (live session identity resolution, playlist playback, enrichment) keeps talking to
/// a single provider and stays untouched by multi-source.
final class MusicSourceRouter: MusicProviderProtocol {

    /// Sources in CONNECTION order. Kept alongside the lookup dictionary because
    /// merge results depend on order — `LibraryAggregator` keeps the first-connected
    /// copy of a duplicate — and dictionary iteration order is unspecified, which
    /// would make the unified library differ between launches.
    private let ordered: [(kind: Track.MusicProvider, provider: MusicProviderProtocol)]
    private let providers: [Track.MusicProvider: MusicProviderProtocol]
    private let ownerByTrackID: [String: Track.MusicProvider]

    init(sources: [(kind: Track.MusicProvider, provider: MusicProviderProtocol, tracks: [Track])]) {
        var providers: [Track.MusicProvider: MusicProviderProtocol] = [:]
        var owners: [String: Track.MusicProvider] = [:]
        for source in sources {
            providers[source.kind] = source.provider
            for track in source.tracks { owners[track.id] = source.kind }
        }
        self.ordered = sources.map { (kind: $0.kind, provider: $0.provider) }
        self.providers = providers
        self.ownerByTrackID = owners
    }

    /// Authorized if ANY connected source still is.
    ///
    /// Each source authorized when it was connected, but that can be revoked later in
    /// iOS Settings — reporting a blanket `true` would turn a revoked permission into
    /// a mysteriously empty library instead of a prompt. Re-asking is cheap and silent
    /// for a source that's still authorized; it only prompts where a prompt is owed.
    func requestAuthorization() async -> Bool {
        var authorized = false
        for source in ordered where await source.provider.requestAuthorization() {
            authorized = true   // keep going: every source gets its chance to re-auth
        }
        return authorized
    }

    /// The unified library, folded the same way `AppCoordinator` folds it: sources in
    /// connection order, duplicates deduped by recording. Anyone calling the protocol
    /// gets what the runner sees, not a raw concatenation with every song twice.
    ///
    /// A source that fails contributes nothing rather than failing the whole fetch —
    /// one flaky service shouldn't empty a library assembled from several.
    func fetchLibraryTracks() async throws -> [Track] {
        var perSource: [[Track]] = []
        for source in ordered {
            perSource.append((try? await source.provider.fetchLibraryTracks()) ?? [])
        }
        return LibraryAggregator.merged(perSource)
    }

    func play(track: Track) async throws {
        // A track's own `provider` field is the fallback for ids the mapping hasn't
        // seen (e.g. a playlist entry added after the last library refresh).
        try await provider(for: track.id, fallback: track.provider)?.play(track: track)
    }

    func analyzableURL(forTrackID id: String) async -> URL? {
        await provider(for: id)?.analyzableURL(forTrackID: id)
    }

    func catalogISRC(forTrackID id: String) async -> String? {
        await provider(for: id)?.catalogISRC(forTrackID: id)
    }

    private func provider(for trackID: String,
                          fallback: Track.MusicProvider? = nil) -> MusicProviderProtocol? {
        // Resolve to a CONNECTED provider, not merely to a kind: a playlist entry can
        // name a service the runner has since toggled out of the mix, and committing
        // to that kind would return nil and fail playback silently — even with another
        // source perfectly able to play it.
        if let kind = ownerByTrackID[trackID], let provider = providers[kind] { return provider }
        if let fallback, let provider = providers[fallback] { return provider }
        // Last resort for unknown ids: with one source there is no ambiguity.
        return ordered.count == 1 ? ordered.first?.provider : nil
    }
}
