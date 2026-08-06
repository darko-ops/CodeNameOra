import Foundation

/// Static configuration for the Spotify integration (Section 6.2).
/// `clientID` comes from Secrets.xcconfig → Info.plist → `Config` (Section 8).
enum SpotifyConfig {
    static var clientID: String { Config.spotifyClientID }

    /// Must match a Redirect URI registered in the Spotify app dashboard exactly.
    static let redirectURI = "dromo://spotify-callback"
    static let callbackScheme = "dromo"

    /// Library read + playback control (App Remote / Web playback).
    ///
    /// `user-library-read` covers saved songs and saved albums, but playlists need their
    /// own grants — without these two, `/me/playlists` answers 403 and the playlist
    /// shelf comes back silently empty.
    static let scopes = [
        "user-library-read",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-read-playback-state",
        "user-modify-playback-state",
        "streaming",
    ].joined(separator: " ")

    /// Bumped when `scopes` changes. A token minted under the old set is still valid and
    /// refreshes happily, but it carries the old grants — so it would keep 403ing on
    /// playlists forever with nothing to indicate why. Comparing this against what was
    /// stored at sign-in is what triggers a re-authorization.
    static let scopeVersion = 2

    static let authorizeEndpoint = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenEndpoint = URL(string: "https://accounts.spotify.com/api/token")!
    static let apiBase = URL(string: "https://api.spotify.com/v1")!

    /// True once a client ID has been supplied — used to pick the real provider
    /// over the mock at runtime without any code change.
    static var isConfigured: Bool { !clientID.isEmpty }
}

enum SpotifyError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case noActiveDevice
    case premiumRequired
    case cancelled
    case cannotStartSession
    case stateMismatch
    case authFailed(String)
    case rateLimited(retryAfter: Double)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:     return "No SPOTIFY_CLIENT_ID set. Add it to Secrets.xcconfig."
        case .notAuthenticated:  return "Not signed in to Spotify."
        case .noActiveDevice:
            return "Open Spotify and start playing anything for a moment, then come "
                + "back — Dromo plays through your Spotify app, and it has to be awake."
        case .premiumRequired:
            // Not something the app can work around: Spotify only exposes playback
            // control to Premium accounts, for both the Web API and the App Remote SDK.
            return "Spotify only lets apps start playback for Premium accounts. Your "
                + "saved songs still count towards your library and their tempo — but "
                + "to hear them on a run, play through Apple Music or Spotify Premium."
        case .cancelled:         return "Spotify sign-in was cancelled."
        case .cannotStartSession:return "Couldn't start the Spotify sign-in session."
        case .stateMismatch:     return "Spotify auth state mismatch (possible CSRF)."
        case .authFailed(let m): return "Spotify authorization failed: \(m)."
        case .rateLimited(let after):
            return "Spotify is limiting requests — retrying in \(Int(after))s."
        case .http(let code, let m): return "Spotify API error \(code): \(m)."
        }
    }
}
