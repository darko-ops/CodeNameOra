import Foundation
import DromoCore

/// Thin Spotify Web API client for the pieces Dromo needs: the user's saved
/// library, per-track tempo (BPM), and playback control.
///
/// ⚠️ BPM caveat: `/v1/audio-features` was restricted by Spotify (Nov 2024) for
/// new apps and apps in development mode. `bpm(forIDs:)` degrades gracefully —
/// it returns whatever it can and surfaces `lastAudioFeaturesForbidden` so the
/// UI can explain why tracks may lack tempo.
actor SpotifyWebAPI {

    private let auth: SpotifyAuthService

    /// Set when the last audio-features call was rejected (403) — i.e. this app
    /// does not have tempo access and BPM must come from another source.
    private(set) var lastAudioFeaturesForbidden = false

    init(auth: SpotifyAuthService) {
        self.auth = auth
    }

    // MARK: - Library

    /// Fetches up to `maxTracks` saved songs, with BPM attached where Spotify will
    /// give it.
    ///
    /// Tracks with no tempo are **kept**, carrying `bpm: 0` ("unknown"), the same way
    /// `AppleMusicProvider` returns an untagged library. Dropping them instead meant
    /// that once Spotify restricted `/v1/audio-features` — which 403s for new apps, so
    /// `bpm(forIDs:)` legitimately returns nothing — every saved track failed the BPM
    /// guard and the runner's entire library vanished. Tempo is filled in afterwards by
    /// `LibraryEnrichmentPass`, which exists precisely to resolve `bpm <= 0` tracks
    /// through the Global Track Table and GetSongBPM. Tempo is required to *pace* a
    /// song, not to *show* one.
    func savedTracks(maxTracks: Int = 200) async throws -> [Track] {
        var dtos: [SpotifyTrackDTO] = []
        var url: URL? = SpotifyConfig.apiBase
            .appendingPathComponent("me/tracks")
            .appending(queryItems: [URLQueryItem(name: "limit", value: "50")])

        while let next = url, dtos.count < maxTracks {
            let page: SpotifySavedTracksPage = try await get(next)
            dtos.append(contentsOf: page.items.map(\.track))
            url = page.next.flatMap(URL.init(string:))
        }

        let ids = dtos.compactMap(\.id)
        let bpmByID = await bpm(forIDs: ids)
        return Self.tracks(from: dtos, bpmByID: bpmByID)
    }

    /// Maps saved-track DTOs to `Track`s. Pure, so the "an untagged library is still a
    /// library" rule can be tested without a network round-trip — it is the rule that
    /// broke, and it broke silently.
    static func tracks(from dtos: [SpotifyTrackDTO],
                       bpmByID: [String: Double]) -> [Track] {
        dtos.compactMap { dto -> Track? in
            // Only an id is required — that's what makes a track addressable. Tempo is
            // optional here, and 0 means "not known yet", not "unusable".
            guard let id = dto.id else { return nil }
            return Track(
                id: id,
                title: dto.name,
                artist: dto.primaryArtist,
                bpm: bpmByID[id] ?? 0,
                energyLevel: 0.5,
                durationSeconds: (dto.duration_ms ?? 0) / 1000,
                provider: .spotify
            )
        }
    }

    // MARK: - BPM (audio features)

    /// Batched tempo lookup (100 IDs/request). Returns id → BPM for whatever the
    /// account is permitted to read; empty if the endpoint is forbidden.
    func bpm(forIDs ids: [String]) async -> [String: Double] {
        var result: [String: Double] = [:]
        for chunk in ids.chunked(into: 100) {
            let url = SpotifyConfig.apiBase
                .appendingPathComponent("audio-features")
                .appending(queryItems: [URLQueryItem(name: "ids", value: chunk.joined(separator: ","))])
            do {
                let batch: SpotifyAudioFeaturesBatch = try await get(url)
                for feature in batch.audio_features.compactMap({ $0 }) where feature.tempo > 0 {
                    result[feature.id] = feature.tempo
                }
            } catch SpotifyError.http(let code, _) where code == 403 {
                lastAudioFeaturesForbidden = true
                break   // no point retrying further chunks
            } catch {
                // Transient error — skip this chunk, keep what we have.
            }
        }
        return result
    }

    // MARK: - Playback (Web API fallback; requires an active device + Premium)

    /// Start a track on the runner's Spotify.
    ///
    /// Without the App Remote SDK this is the only playback path, and `/me/player/play`
    /// will only talk to an **already-active** device — with none it answers 404
    /// NO_ACTIVE_DEVICE, which is what "nothing happens when I tap a song" looks like.
    /// A Spotify app sitting idle in the background is listed but not active, so the
    /// device is resolved and named explicitly rather than left to a default that
    /// usually isn't there.
    func play(trackID: String) async throws {
        let device = try? await activeOrAvailableDevice()

        var url = SpotifyConfig.apiBase.appendingPathComponent("me/player/play")
        if let device {
            url = url.appending(queryItems: [URLQueryItem(name: "device_id", value: device.id)])
        }
        let body = try JSONSerialization.data(withJSONObject: ["uris": ["spotify:track:\(trackID)"]])

        do {
            _ = try await send(url, method: "PUT", body: body, decodeEmpty: true)
        } catch SpotifyError.http(let code, _) where code == 403 {
            // Playback control is Premium-only, for the Web API and App Remote alike.
            // Distinct from "no device": there is nothing the runner can do to their
            // setup that would make this call succeed.
            throw SpotifyError.premiumRequired
        } catch SpotifyError.http(let code, _) where code == 404 {
            // Spotify distinguishes "no device" from "device asleep" only loosely, so
            // say the actionable thing rather than repeat its wording.
            throw SpotifyError.noActiveDevice
        }
    }

    /// The account's Spotify plan, from `GET /me` — "premium", "free", or "open".
    ///
    /// Checked when connecting rather than discovered on the first tap, so a free
    /// account is told up front that Dromo can read its library but can't play it.
    func accountIsPremium() async -> Bool? {
        let url = SpotifyConfig.apiBase.appendingPathComponent("me")
        guard let profile: SpotifyProfile = try? await get(url) else { return nil }
        return profile.product == "premium"
    }

    /// The device Spotify is on, preferring one that's already active.
    private func activeOrAvailableDevice() async throws -> SpotifyDevice {
        let url = SpotifyConfig.apiBase.appendingPathComponent("me/player/devices")
        let list: SpotifyDevicesResponse = try await get(url)
        guard let device = Self.preferredDevice(from: list.devices) else {
            throw SpotifyError.noActiveDevice
        }
        return device
    }

    /// Pick where to play: an already-active device first, otherwise any that Spotify
    /// lists, since an idle app can still be told to start. Devices without an id can't
    /// be targeted at all.
    static func preferredDevice(from devices: [SpotifyDevice]) -> SpotifyDevice? {
        let addressable = devices.filter { $0.id != nil }
        return addressable.first(where: \.is_active) ?? addressable.first
    }

    // MARK: - Request plumbing

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let data = try await send(url, method: "GET", body: nil, decodeEmpty: false)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private func send(_ url: URL, method: String, body: Data?, decodeEmpty: Bool) async throws -> Data {
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw SpotifyError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}

// MARK: - Helpers

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}

// `URL.appending(queryItems:)` is provided by Foundation on iOS 16+.
