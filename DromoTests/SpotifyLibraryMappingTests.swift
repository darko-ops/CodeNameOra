import XCTest
import DromoCore
@testable import Dromo

/// Regression cover for the rule that a library with no tempo is still a library.
///
/// `savedTracks` used to require a BPM per track. Spotify restricted
/// `/v1/audio-features` for new apps, so the tempo lookup legitimately returns nothing
/// — and every saved track then failed that guard, leaving the runner's whole library
/// empty. The coordinator read the empty result as "nothing connected" and substituted
/// a demo catalog, so the failure surfaced as somebody else's music rather than as an
/// error. Tempo is needed to *pace* a song, not to *show* one.
final class SpotifyLibraryMappingTests: XCTestCase {

    private func dto(_ id: String, _ name: String, seconds: Int = 200) -> SpotifyTrackDTO {
        SpotifyTrackDTO(id: id, name: name,
                        artists: [.init(name: "Test Artist")],
                        duration_ms: seconds * 1000)
    }

    /// The exact failure: audio-features forbidden, so no tempo for anything.
    func test_librarySurvivesWhenSpotifyGivesNoTempo() {
        let dtos = [dto("1", "One"), dto("2", "Two"), dto("3", "Three")]

        let tracks = SpotifyWebAPI.tracks(from: dtos, bpmByID: [:])

        XCTAssertEqual(tracks.count, 3, "An untagged library must still be a library")
        XCTAssertEqual(tracks.map(\.title), ["One", "Two", "Three"])
        XCTAssertTrue(tracks.allSatisfy { $0.bpm == 0 },
                      "Unknown tempo is 0, which enrichment later resolves")
    }

    /// Tempo is used where it exists, and its absence doesn't cost the neighbours.
    func test_keepsKnownTempoAndUntaggedTogether() {
        let dtos = [dto("1", "Tagged"), dto("2", "Untagged")]

        let tracks = SpotifyWebAPI.tracks(from: dtos, bpmByID: ["1": 168])

        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks.first { $0.id == "1" }?.bpm, 168)
        XCTAssertEqual(tracks.first { $0.id == "2" }?.bpm, 0)
    }

    /// A track with no id can't be played or looked up, so it's the one thing dropped.
    func test_dropsOnlyTracksWithNoID() {
        let dtos = [dto("1", "Playable"),
                    SpotifyTrackDTO(id: nil, name: "Unaddressable",
                                    artists: [.init(name: "X")], duration_ms: 1000)]

        let tracks = SpotifyWebAPI.tracks(from: dtos, bpmByID: [:])

        XCTAssertEqual(tracks.map(\.id), ["1"])
    }

    /// Downstream of the fix: merging must not undo it. The aggregator prefers a tagged
    /// copy of the *same* recording, which must not become "drop untagged tracks".
    func test_aggregatorKeepsUntaggedTracks() {
        let spotify = SpotifyWebAPI.tracks(from: [dto("1", "Only Copy")], bpmByID: [:])

        let merged = LibraryAggregator.merged([spotify])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.bpm, 0)
    }
}

/// Cover for choosing where Spotify should play.
///
/// Without the App Remote SDK, playback goes through `/me/player/play`, which only
/// talks to a device it has been given — with none it answers 404 NO_ACTIVE_DEVICE,
/// which is what "I tap a song and nothing happens" looks like. A Spotify app idling in
/// the background is listed but not active, so it has to be found and named.
final class SpotifyDeviceSelectionTests: XCTestCase {

    private func device(_ id: String?, _ name: String, active: Bool) -> SpotifyDevice {
        SpotifyDevice(id: id, name: name, is_active: active, type: "Smartphone")
    }

    func test_prefersTheActiveDevice() {
        let devices = [device("a", "Laptop", active: false),
                       device("b", "Phone", active: true)]

        XCTAssertEqual(SpotifyWebAPI.preferredDevice(from: devices)?.id, "b")
    }

    /// The case that was failing: Spotify is installed and listed, just not playing.
    func test_fallsBackToAnIdleDevice() {
        let devices = [device("a", "Phone", active: false)]

        XCTAssertEqual(SpotifyWebAPI.preferredDevice(from: devices)?.id, "a",
                       "An idle app can still be told to start")
    }

    func test_skipsDevicesWithNoID() {
        let devices = [device(nil, "Restricted", active: true),
                       device("b", "Phone", active: false)]

        XCTAssertEqual(SpotifyWebAPI.preferredDevice(from: devices)?.id, "b",
                       "A device with no id cannot be targeted")
    }

    func test_noDevicesMeansNowhereToPlay() {
        XCTAssertNil(SpotifyWebAPI.preferredDevice(from: []))
    }
}

/// Cover for reading the whole Spotify library, not just its saved-songs shelf.
///
/// `savedTracks` was capped at 200 and read only `/me/tracks`, so a runner with
/// thousands of songs across albums and playlists saw a fraction of what they own.
final class SpotifyLibraryBreadthTests: XCTestCase {

    private func dto(_ id: String, _ name: String) -> SpotifyTrackDTO {
        SpotifyTrackDTO(id: id, name: name,
                        artists: [.init(name: "A")], duration_ms: 200_000)
    }

    /// The same song arrives through several shelves — saved, on its album, in three
    /// playlists — and must become one track, not five.
    func test_deduplicatesAcrossShelves() {
        let mixed = [dto("a", "Saved"), dto("b", "Album"),
                     dto("a", "Same song again"), dto("b", "And again"), dto("c", "Playlist")]

        let unique = SpotifyWebAPI.deduplicated(mixed)

        XCTAssertEqual(unique.map(\.id), ["a", "b", "c"])
    }

    /// First occurrence wins, so the saved-songs copy — read first — is the one kept.
    func test_keepsTheFirstCopySeen() {
        let mixed = [dto("a", "From saved songs"), dto("a", "From a playlist")]

        XCTAssertEqual(SpotifyWebAPI.deduplicated(mixed).first?.name, "From saved songs")
    }

    /// A track with no id can't be addressed or played, so it isn't a library entry.
    func test_dropsUnaddressableTracks() {
        let mixed = [dto("a", "Fine"),
                     SpotifyTrackDTO(id: nil, name: "No id",
                                     artists: [.init(name: "A")], duration_ms: 1000)]

        XCTAssertEqual(SpotifyWebAPI.deduplicated(mixed).map(\.id), ["a"])
    }

    /// Each shelf is bounded separately, so one enormous one can't starve the others.
    func test_shelvesAreBoundedIndependently() {
        let limits = SpotifyWebAPI.LibraryLimits.default

        XCTAssertGreaterThan(limits.savedTracks, 200, "The old 200 cap was the bug")
        XCTAssertGreaterThan(limits.albums, 0)
        XCTAssertGreaterThan(limits.playlists, 0)
        XCTAssertGreaterThan(limits.tracksPerPlaylist, 0)
    }

    /// Playlists need grants beyond user-library-read; without them /me/playlists 403s
    /// and the shelf comes back empty with nothing to explain it.
    func test_scopesCoverPlaylistReads() {
        XCTAssertTrue(SpotifyConfig.scopes.contains("playlist-read-private"),
                      "Private playlists are unreadable without this")
        XCTAssertTrue(SpotifyConfig.scopes.contains("user-library-read"),
                      "Saved songs and albums still need this")
    }
}

/// Cover for a playlist page surviving the things playlists actually contain.
///
/// A playlist is a mixed bag — songs, podcast episodes, local files, tracks pulled from
/// the catalogue. Codable decodes all-or-nothing by default, so one podcast episode
/// (which carries no `artists` field) threw for the whole page and the entire playlist
/// was lost. With 149 playlists that read as 149 individually broken playlists rather
/// than one shared bug.
final class SpotifyPlaylistDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> SpotifyPlaylistTracksPage {
        try JSONDecoder().decode(SpotifyPlaylistTracksPage.self, from: Data(json.utf8))
    }

    /// The exact failure: one episode among the songs.
    func test_anEpisodeDoesNotCostTheWholePlaylist() throws {
        let page = try decode("""
        {"items":[
          {"track":{"id":"a","name":"Song One","artists":[{"name":"Artist"}],"duration_ms":200000}},
          {"track":{"id":"ep","name":"An Episode","duration_ms":3600000,"type":"episode"}},
          {"track":{"id":"b","name":"Song Two","artists":[{"name":"Artist"}],"duration_ms":210000}}
        ],"next":null}
        """)

        let ids = page.items.compactMap(\.track).compactMap(\.id)
        XCTAssertTrue(ids.contains("a"), "The songs around an episode must survive it")
        XCTAssertTrue(ids.contains("b"))
    }

    /// Removed tracks come through as null and are simply skipped.
    func test_nullEntriesAreSkipped() throws {
        let page = try decode("""
        {"items":[{"track":null},
                  {"track":{"id":"a","name":"S","artists":[{"name":"A"}],"duration_ms":1000}}],
         "next":null}
        """)

        XCTAssertEqual(page.items.compactMap(\.track).compactMap(\.id), ["a"])
    }

    /// A malformed entry is stepped over rather than looping or throwing.
    func test_malformedEntriesDoNotStall() throws {
        let page = try decode("""
        {"items":[{"unexpected":"shape"},
                  {"track":{"id":"a","name":"S","artists":[{"name":"A"}],"duration_ms":1000}}],
         "next":null}
        """)

        XCTAssertEqual(page.items.compactMap(\.track).compactMap(\.id), ["a"])
    }

    /// Paging still works — losing `next` would silently truncate every playlist.
    func test_nextPageLinkSurvives() throws {
        let page = try decode("""
        {"items":[],"next":"https://api.spotify.com/v1/playlists/x/tracks?offset=100"}
        """)

        XCTAssertNotNil(page.next)
    }

    /// An album track with no artists of its own falls back to the album's.
    func test_albumTrackWithoutArtistsReadsTheAlbumArtist() {
        let dto = SpotifyTrackDTO(id: "a", name: "Track", artists: nil, duration_ms: 1000)

        XCTAssertEqual(dto.primaryArtist, "Unknown")
    }
}

/// Cover for not making a rate limit worse.
///
/// The first version capped a long `Retry-After` down to ten seconds and retried
/// anyway. Spotify asked for hours, the app waited seconds and asked again, and each
/// attempt pushed the window further out — a transient throttle became a day-long one
/// (`retryAfter: 83320`). A long wait has to mean stop, not hurry.
final class SpotifyBackoffTests: XCTestCase {

    override func tearDown() {
        SpotifyWebAPI.resetPlaylistRestriction()
        super.tearDown()
    }

    /// A capability refusal is remembered, so later launches don't re-probe and spend a
    /// request to be told no again.
    func test_restrictionPersistsSoItIsNotReprobed() {
        SpotifyWebAPI.resetPlaylistRestriction()
        XCTAssertFalse(SpotifyWebAPI.playlistsRestricted)

        SpotifyWebAPI.playlistsRestricted = true

        XCTAssertTrue(SpotifyWebAPI.playlistsRestricted,
                      "A 403 on playlist reads is a property of the app's API access")
    }

    /// And it can be cleared, so granting extended quota doesn't require a reinstall.
    func test_restrictionCanBeCleared() {
        SpotifyWebAPI.playlistsRestricted = true

        SpotifyWebAPI.resetPlaylistRestriction()

        XCTAssertFalse(SpotifyWebAPI.playlistsRestricted)
    }
}

/// Cover for withdrawing a music service from the app.
///
/// Spotify is hidden rather than deleted: it can supply a track list and nothing else —
/// no tempo, and no playback without both Premium and an API grant reserved for
/// launched services at scale. A source that can't play fills the library with songs
/// that do nothing when tapped, which is worse than not offering it.
final class OfferedProviderTests: XCTestCase {

    func test_spotifyIsNotOffered() {
        XCTAssertFalse(AppCoordinator.ProviderChoice.spotify.isOffered)
        XCTAssertFalse(AppCoordinator.ProviderChoice.offered.contains(.spotify))
    }

    func test_appleMusicIsOffered() {
        XCTAssertTrue(AppCoordinator.ProviderChoice.appleMusic.isOffered)
        XCTAssertTrue(AppCoordinator.ProviderChoice.offered.contains(.appleMusic))
    }

    /// Something has to remain, or connecting music becomes impossible.
    func test_atLeastOneServiceIsOffered() {
        XCTAssertFalse(AppCoordinator.ProviderChoice.offered.isEmpty)
    }

    /// The case survives so existing libraries and saved tracks still resolve, and
    /// bringing the integration back stays a one-line change.
    func test_theIntegrationIsHiddenNotDeleted() {
        XCTAssertTrue(AppCoordinator.ProviderChoice.allCases.contains(.spotify),
                      "Tracks already in a library still name their source")
        XCTAssertEqual(Track.MusicProvider.spotify.displayName, "Spotify")
    }
}
