import Foundation
import os
import DromoCore

private let spotifyBPMLog = Logger(subsystem: "com.daed.dromo", category: "spotify-bpm")

/// Resolves a track's BPM from **Spotify Audio Features**, keyed by title + artist —
/// used purely as a background metadata database. The user never signs into Spotify;
/// this uses the **Client Credentials** flow (app-level token, no user OAuth), so it
/// can supply BPM for Apple Music tracks Dromo can't analyze on-device.
///
/// Actor: serializes the cached app token across concurrent lookups.
///
/// ⚠️ Spotify restricted the Audio Features endpoint for new apps (late 2024). If your
/// app tier lacks access, these calls return non-200 → nil, and the enrichment chain
/// falls back to GetSongBPM. Verify/request quota at developer.spotify.com.
actor SpotifyBPMResolver: BPMLookup {
    private let clientID: String
    private let clientSecret: String
    private let session: URLSession
    private var token: String?
    private var tokenExpiry: Date?
    private var loggedOnce = false   // log the first outcome so we know token vs 403 vs network
    private var disabled = false     // trips on a 403 so we stop hammering a restricted tier

    private func noteOnce(_ message: String) {
        guard !loggedOnce else { return }
        loggedOnce = true
        spotifyBPMLog.notice("\(message, privacy: .public)")
        print("🎚️ [spotify-bpm] \(message)")
    }

    init(clientID: String, clientSecret: String, session: URLSession = .shared) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.session = session
    }

    func bpm(title: String, artist: String) async -> Double? {
        guard !disabled, !clientID.isEmpty, !clientSecret.isEmpty else { return nil }
        do {
            guard let trackID = try await searchTrackID(title: title, artist: artist) else {
                noteOnce("token+search OK but no track match for an item (coverage gap)")
                return nil
            }
            let tempo = try await audioFeaturesTempo(trackID)
            if tempo != nil { noteOnce("working — got a tempo from audio-features ✅") }
            return tempo
        } catch {
            noteOnce("FAILED: \(error.localizedDescription) (network/token — not a clean 403)")
            return nil
        }
    }

    // MARK: - Steps

    private func accessToken() async throws -> String {
        if let token, let tokenExpiry, Date() < tokenExpiry { return token }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        let creds = Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(creds)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("grant_type=client_credentials".utf8)

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let parsed = Self.parseToken(data) else { throw URLError(.userAuthenticationRequired) }
        token = parsed.token
        tokenExpiry = Date().addingTimeInterval(Double(parsed.expiresIn - 60))
        return parsed.token
    }

    private func searchTrackID(title: String, artist: String) async throws -> String? {
        let token = try await accessToken()
        let query = "\(title) \(artist)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "https://api.spotify.com/v1/search?q=\(query)&type=track&limit=1")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else { noteOnce("search HTTP \(code)"); return nil }
        return Self.parseFirstTrackID(data)
    }

    private func audioFeaturesTempo(_ trackID: String) async throws -> Double? {
        let token = try await accessToken()
        let url = URL(string: "https://api.spotify.com/v1/audio-features/\(trackID)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else {
            if code == 403 { disabled = true }   // restricted tier — stop trying for this session
            noteOnce("audio-features HTTP \(code)\(code == 403 ? " — RESTRICTED TIER; disabling Spotify, falling back to GetSongBPM" : "")")
            return nil
        }
        return Self.parseTempo(data)
    }

    // MARK: - Parsers (testable, decoder-only)

    static func parseToken(_ data: Data) -> (token: String, expiresIn: Int)? {
        struct R: Decodable { let access_token: String; let expires_in: Int }
        guard let r = try? JSONDecoder().decode(R.self, from: data) else { return nil }
        return (r.access_token, r.expires_in)
    }

    static func parseFirstTrackID(_ data: Data) -> String? {
        struct R: Decodable {
            struct Tracks: Decodable { struct Item: Decodable { let id: String }; let items: [Item] }
            let tracks: Tracks?
        }
        return (try? JSONDecoder().decode(R.self, from: data))?.tracks?.items.first?.id
    }

    static func parseTempo(_ data: Data) -> Double? {
        struct R: Decodable { let tempo: Double? }
        guard let tempo = (try? JSONDecoder().decode(R.self, from: data))?.tempo, tempo > 60 else {
            return nil
        }
        return tempo
    }
}
