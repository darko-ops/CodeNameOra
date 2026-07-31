import SwiftUI
import DromoCore

/// Backs the Sound tab. Organizes the library into browsable sections — the tempo
/// ladder, your (user-created) playlists, a high-energy shelf — and holds the search and
/// BPM-filter state that `AllTracksView` browses the full library through.
///
/// Everything here is the runner's own music. Nothing is substituted when a section
/// would be empty.
@MainActor
final class PlaylistsViewModel: ObservableObject {
    @Published private(set) var libraryTracks: [Track] = []
    @Published private(set) var userPlaylists: [Playlist] = []   // user-created
    /// The top of the library by energy, capped — an editorial shelf, not a ranking.
    /// Named for what it measures: the provider gives us no play counts, so the old
    /// `popular` was never popularity.
    @Published private(set) var highEnergy: [Track] = []
    @Published private(set) var tempoPlaylists: [Playlist] = []

    // MARK: - Browse state (All tracks)

    /// What the runner typed. Matches title and artist, and a bare number reads as a BPM
    /// query. Debounced into `activeQuery`: `libraryTracks` runs to thousands of rows and
    /// re-filtering on every keystroke is felt.
    @Published var query: String = "" {
        didSet { scheduleQueryDebounce() }
    }
    @Published private(set) var activeQuery: String = ""
    /// The selected tempo window, or nil for "All BPM".
    @Published var bpmFilter: PlaylistCatalog.Bucket?
    @Published var sort: TrackSort = .bpmAscending

    enum TrackSort: String, CaseIterable, Identifiable {
        case bpmAscending = "BPM ↑"
        case title = "Title"
        case artist = "Artist"
        var id: String { rawValue }
    }

    private let repo = PlaylistRepository()
    private var libraryByID: [String: Track] = [:]
    private var debounce: Task<Void, Never>?

    // MARK: - Loading

    func load(from library: [Track]) async {
        // The runner's own music only — no demo catalog standing in for an empty
        // library. An empty Sound tab is the honest answer to "nothing is connected
        // yet", and the sections say so.
        let source = library
        libraryTracks = source
        libraryByID = Dictionary(source.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        tempoPlaylists = PlaylistCatalog.playlists(from: source)
        highEnergy = Array(source.sorted { $0.energyLevel > $1.energyLevel }.prefix(15))
        await reloadUserPlaylists()
    }

    /// How many library tracks carry a tempo — what the All-tracks entry card reports,
    /// since that is what the screen can actually sort and filter by.
    var taggedCount: Int { libraryTracks.filter { $0.bpm > 0 }.count }

    // MARK: - Filtering

    /// The library narrowed by the active query and BPM window, then sorted.
    ///
    /// Untagged tracks survive a text search — the runner knows they own the song, and
    /// dropping it silently looks like a bug — but a BPM filter excludes them, and they
    /// sort last under `BPM ↑`, having no place on that scale.
    var filteredTracks: [Track] {
        var result = libraryTracks

        if let bucket = bpmFilter {
            result = result.filter { bucket.contains($0.bpm) }
        }

        let q = activeQuery.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            if let bpm = Double(q) {
                // A bare number reads as a tempo query: everything within ±2 BPM.
                result = result.filter { $0.bpm > 0 && abs($0.bpm - bpm) <= 2 }
            } else {
                result = result.filter {
                    $0.title.localizedCaseInsensitiveContains(q)
                        || $0.artist.localizedCaseInsensitiveContains(q)
                }
            }
        }

        switch sort {
        case .bpmAscending:
            // Untagged last, then by tempo, then title so equal-BPM runs stay stable.
            result.sort {
                switch ($0.bpm > 0, $1.bpm > 0) {
                case (true, false): return true
                case (false, true): return false
                case (false, false): return $0.title.localizedCompare($1.title) == .orderedAscending
                case (true, true):
                    if $0.bpm != $1.bpm { return $0.bpm < $1.bpm }
                    return $0.title.localizedCompare($1.title) == .orderedAscending
                }
            }
        case .title:
            result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .artist:
            result.sort { $0.artist.localizedCompare($1.artist) == .orderedAscending }
        }
        return result
    }

    func clearQuery() {
        debounce?.cancel()
        query = ""
        activeQuery = ""
    }

    private func scheduleQueryDebounce() {
        debounce?.cancel()
        let pending = query
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.activeQuery = pending
        }
    }

    // MARK: - User playlists

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
            // The accent is vestigial: these rows are a neutral list now and nothing
            // reads it. Kept on-token rather than removed, since `Playlist` is shared
            // with the tempo ladder, where the accent still does work.
            return Playlist(
                id: record.id, name: record.name, subtitle: "For your sessions",
                systemImage: "music.note.list", accentHex: "#6EA8C9", tracks: tracks)
        }
    }
}

extension Playlist {
    /// "8 tracks · 128–164 BPM" — a user playlist row's subtitle, dropping the range
    /// when nothing in it is tagged to derive one from.
    var trackSummary: String {
        let count = "\(tracks.count) track\(tracks.count == 1 ? "" : "s")"
        let tagged = tracks.map(\.bpm).filter { $0 > 0 }
        guard let lo = tagged.min(), let hi = tagged.max() else { return count }
        return lo == hi
            ? "\(count) · \(Int(lo)) BPM"
            : "\(count) · \(Int(lo))–\(Int(hi)) BPM"
    }
}
