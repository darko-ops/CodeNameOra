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

    /// Fetches up to `maxTracks` saved songs and enriches them with BPM.
    /// Tracks without a usable BPM are dropped (the sequencer needs tempo).
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

        return dtos.compactMap { dto -> Track? in
            guard let id = dto.id, let bpm = bpmByID[id], bpm > 0 else { return nil }
            return Track(
                id: id,
                title: dto.name,
                artist: dto.primaryArtist,
                bpm: bpm,
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

    func play(trackID: String) async throws {
        let url = SpotifyConfig.apiBase.appendingPathComponent("me/player/play")
        let body = try JSONSerialization.data(withJSONObject: ["uris": ["spotify:track:\(trackID)"]])
        _ = try await send(url, method: "PUT", body: body, decodeEmpty: true)
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
