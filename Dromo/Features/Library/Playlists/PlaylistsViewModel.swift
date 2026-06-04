import SwiftUI
import DromoCore

/// Backs the Sound tab. Organizes the library into browsable sections — your
/// (user-created) playlists, your tracks, popular, and the pre-built tempo playlists.
/// Falls back to the demo catalog so the tab is never empty.
@MainActor
final class PlaylistsViewModel: ObservableObject {
    @Published private(set) var libraryTracks: [Track] = []
    @Published private(set) var userPlaylists: [Playlist] = []   // user-created
    @Published private(set) var popular: [Track] = []
    @Published private(set) var tempoPlaylists: [Playlist] = []

    private let repo = PlaylistRepository()
    private var libraryByID: [String: Track] = [:]

    func load(from library: [Track]) async {
        let source = library.isEmpty ? MockMusicCatalog.tracks : library
        libraryTracks = source
        libraryByID = Dictionary(source.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        tempoPlaylists = PlaylistCatalog.playlists(from: source)
        popular = Array(source.sorted { $0.energyLevel > $1.energyLevel }.prefix(15))
        await reloadUserPlaylists()
    }

    func createPlaylist(name: String, trackIDs: [String]) async {
        await repo.create(name: name, trackIDs: trackIDs)
        await reloadUserPlaylists()
    }

    func renamePlaylist(id: String, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        await repo.rename(id: id, name: trimmed)
        await reloadUserPlaylists()
    }

    func deletePlaylist(_ id: String) async {
        await repo.delete(id: id)
        await reloadUserPlaylists()
    }

    private func reloadUserPlaylists() async {
        let records = await repo.all()
        userPlaylists = records.map { record in
            let tracks = record.trackIDs.compactMap { libraryByID[$0] }
            return Playlist(
                id: record.id, name: record.name, subtitle: "For your sessions",
                systemImage: "music.note.list", accentHex: "#22D3EE", tracks: tracks)
        }
    }
}
