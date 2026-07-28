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

    private let providers: [Track.MusicProvider: MusicProviderProtocol]
    private let ownerByTrackID: [String: Track.MusicProvider]

    init(sources: [(kind: Track.MusicProvider, provider: MusicProviderProtocol, tracks: [Track])]) {
        var providers: [Track.MusicProvider: MusicProviderProtocol] = [:]
        var owners: [String: Track.MusicProvider] = [:]
        for source in sources {
            providers[source.kind] = source.provider
            for track in source.tracks { owners[track.id] = source.kind }
        }
        self.providers = providers
        self.ownerByTrackID = owners
    }

    /// Every underlying source authorized when it was connected.
    func requestAuthorization() async -> Bool { true }

    func fetchLibraryTracks() async throws -> [Track] {
        var all: [Track] = []
        for provider in providers.values {
            all += (try? await provider.fetchLibraryTracks()) ?? []
        }
        return all
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
        if let kind = ownerByTrackID[trackID] ?? fallback { return providers[kind] }
        // Last resort for unknown ids: with one source there is no ambiguity.
        return providers.count == 1 ? providers.values.first : nil
    }
}
