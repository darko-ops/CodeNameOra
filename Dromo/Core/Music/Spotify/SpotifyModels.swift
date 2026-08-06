import Foundation

/// OAuth token bundle, persisted in the Keychain.
struct SpotifyTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    /// Treat as expired a minute early to avoid races near the boundary.
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

/// `POST /api/token` response.
struct SpotifyTokenResponse: Codable {
    let access_token: String
    let token_type: String
    let expires_in: Double
    let refresh_token: String?
    let scope: String?
}

// MARK: - Web API DTOs (only the fields Dromo needs)

struct SpotifySavedTracksPage: Codable {
    let items: [SavedItem]
    let next: String?

    struct SavedItem: Codable { let track: SpotifyTrackDTO }
}

struct SpotifyTrackDTO: Codable {
    let id: String?
    let name: String
    /// Optional because a playlist holds more than songs. Podcast episodes carry no
    /// `artists` at all, and a non-optional field here threw on the first one — taking
    /// the whole page, and so the whole playlist, down with it.
    let artists: [Artist]?
    let duration_ms: Int?

    struct Artist: Codable { let name: String }

    var primaryArtist: String { artists?.first?.name ?? "Unknown" }

    init(id: String?, name: String, artists: [Artist]?, duration_ms: Int?) {
        self.id = id
        self.name = name
        self.artists = artists
        self.duration_ms = duration_ms
    }
}

/// `GET /audio-features` — the (now access-restricted) tempo source.
struct SpotifyAudioFeaturesBatch: Codable {
    let audio_features: [Feature?]
    struct Feature: Codable {
        let id: String
        let tempo: Double
        let energy: Double?
    }
}

/// `GET /me/player/devices` — where the runner's Spotify can play.
///
/// Needed because `/me/player/play` targets an active device, and a Spotify app idling
/// in the background is available but not active.
struct SpotifyDevicesResponse: Codable {
    let devices: [SpotifyDevice]
}

struct SpotifyDevice: Codable {
    let id: String?
    let name: String
    let is_active: Bool
    let type: String
}

/// `GET /me` — only the plan is read. "premium" is the one value that permits
/// playback control; free accounts can still expose their saved library.
struct SpotifyProfile: Codable {
    let id: String?
    let product: String?
}

// MARK: - The rest of the library
//
// Saved songs are only one shelf of a Spotify library. Albums and playlists usually
// hold far more, so reading only `/me/tracks` shows a fraction of what the runner owns.

/// `GET /me/albums` — saved albums. Each carries its own track list, so the tracks come
/// back in the same response and need no follow-up request per album.
struct SpotifySavedAlbumsPage: Codable {
    let items: [SavedAlbum]
    let next: String?

    struct SavedAlbum: Codable { let album: Album }

    struct Album: Codable {
        let id: String?
        let name: String
        let artists: [SpotifyTrackDTO.Artist]?
        let tracks: TrackList?

        /// Album tracks omit their own `artists` in some responses, so the album's
        /// artist stands in — otherwise every track on it reads "Unknown".
        var primaryArtist: String { artists?.first?.name ?? "Unknown" }

        struct TrackList: Codable {
            let items: [SpotifyTrackDTO]
            let next: String?
        }
    }
}

/// `GET /me/playlists` — playlists the runner owns or follows. Tracks are a separate
/// request per playlist (`GET /playlists/{id}/tracks`).
struct SpotifyPlaylistsPage: Codable {
    let items: [PlaylistSummary]
    let next: String?

    struct PlaylistSummary: Codable {
        let id: String?
        let name: String
        let tracks: TrackCount?
        /// Who made it. `/me/playlists` returns followed playlists alongside owned
        /// ones, and Spotify refuses item reads on its own editorial and algorithmic
        /// playlists — so the owner is what separates "your music" from "a playlist you
        /// follow that the API will not open".
        let owner: Owner?

        struct TrackCount: Codable { let total: Int? }
        struct Owner: Codable { let id: String? }
    }
}

/// `GET /playlists/{id}/tracks`.
///
/// Decoded leniently, item by item. A playlist is a mixed bag — songs, podcast
/// episodes, local files, tracks pulled from the catalogue — and Codable's default
/// all-or-nothing decoding meant one unexpected entry threw for the entire page, so a
/// single podcast in a playlist of 200 songs lost all 200. Anything that fails to decode
/// is skipped; everything around it still arrives.
struct SpotifyPlaylistTracksPage: Decodable {
    let items: [Item]
    let next: String?

    struct Item: Decodable { let track: SpotifyTrackDTO? }

    private enum CodingKeys: String, CodingKey { case items, next }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        next = try container.decodeIfPresent(String.self, forKey: .next)

        // Decode each entry in isolation so a bad one costs only itself.
        var unkeyed = try container.nestedUnkeyedContainer(forKey: .items)
        var decoded: [Item] = []
        while !unkeyed.isAtEnd {
            if let item = try? unkeyed.decode(Item.self) {
                decoded.append(item)
            } else {
                // Still has to be consumed, or the container never advances and this
                // loops forever on the first malformed entry.
                _ = try? unkeyed.decode(AnyCodableSkip.self)
            }
        }
        items = decoded
    }
}

/// Consumes one element of unknown shape, so a failed decode can be stepped over.
private struct AnyCodableSkip: Decodable {
    init(from decoder: Decoder) throws {
        _ = try? decoder.singleValueContainer()
    }
}
