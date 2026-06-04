import Foundation

/// Typed access to secrets injected via Secrets.xcconfig → Info.plist (Section 8.2).
/// Values are empty in the Phase 0 scaffold until the account-setup checklist is done.
enum Config {
    private static func string(_ key: String) -> String {
        Bundle.main.infoDictionary?[key] as? String ?? ""
    }

    static let spotifyClientID = string("SPOTIFY_CLIENT_ID")
    /// Client-credentials secret — for the background Spotify BPM resolver (no user login).
    static let spotifyClientSecret = string("SPOTIFY_CLIENT_SECRET")
    static let supabaseURL = string("SUPABASE_URL")
    static let supabaseAnonKey = string("SUPABASE_ANON_KEY")
    static let revenueCatAPIKey = string("REVENUECAT_API_KEY")
    static let stravaClientID = string("STRAVA_CLIENT_ID")
    static let stravaClientSecret = string("STRAVA_CLIENT_SECRET")
    static let sentryDSN = string("SENTRY_DSN")
    static let posthogAPIKey = string("POSTHOG_API_KEY")
    /// GetSongBPM — metadata BPM lookup for DRM streaming tracks (no audio needed).
    static let getSongBPMKey = string("GETSONGBPM_API_KEY")
}
