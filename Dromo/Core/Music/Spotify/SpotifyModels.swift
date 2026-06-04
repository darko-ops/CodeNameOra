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
    let artists: [Artist]
    let duration_ms: Int?

    struct Artist: Codable { let name: String }

    var primaryArtist: String { artists.first?.name ?? "Unknown" }
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
