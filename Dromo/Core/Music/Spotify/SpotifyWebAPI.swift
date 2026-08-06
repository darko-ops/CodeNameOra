import Foundation
import os
import DromoCore

/// Traces what each shelf of the library actually returned.
///
/// The shelves fail independently and quietly by design — a dead playlist must not cost
/// the runner the songs already read — which means a shelf returning nothing looks the
/// same as a shelf that was never reachable. This is how to tell them apart:
///
///     Console.app → filter subsystem `com.daed.dromo`, category `spotify-library`
///     (or watch Xcode's console with the app running from a device build)
private let libraryLog = Logger(subsystem: "com.daed.dromo", category: "spotify-library")

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

    /// How much of a library to read. Saved songs, saved albums and playlists each get
    /// their own ceiling so one enormous shelf can't starve the others — a runner with
    /// 3,000 saved songs should still see their albums.
    struct LibraryLimits {
        var savedTracks = 5_000
        var albums = 500
        var playlists = 200
        /// Per playlist. Spotify allows 10,000, but a handful of giant playlists would
        /// otherwise dominate the whole read.
        var tracksPerPlaylist = 1_000

        static let `default` = LibraryLimits()
    }

    /// Everything the runner's Spotify library holds: saved songs, the tracks on saved
    /// albums, and the tracks in their playlists — deduplicated, with BPM attached where
    /// Spotify will give it.
    ///
    /// Saved songs alone are a fraction of a library. Most people keep far more in
    /// albums and playlists, which is why connecting Spotify used to surface so little.
    ///
    /// Tracks with no tempo are **kept**, carrying `bpm: 0` ("unknown"), the same way
    /// `AppleMusicProvider` returns an untagged library. Dropping them instead meant
    /// that once Spotify restricted `/v1/audio-features` — which 403s for new apps, so
    /// `bpm(forIDs:)` legitimately returns nothing — every saved track failed the BPM
    /// guard and the runner's entire library vanished. Tempo is filled in afterwards by
    /// `LibraryEnrichmentPass`. Tempo is required to *pace* a song, not to *show* one.
    func libraryTracks(limits: LibraryLimits = .default) async throws -> [Track] {
        let started = Date()
        var dtos: [SpotifyTrackDTO] = []

        // Saved songs first: if a later shelf hits a limit or errors, the most
        // deliberately-curated music is already in.
        let saved = try await savedTrackDTOs(max: limits.savedTracks)
        dtos += saved
        libraryLog.notice("saved songs: \(saved.count, privacy: .public)")

        // Albums and playlists are best-effort — a failure there must not cost the
        // runner the songs already read. Each failure is logged rather than swallowed,
        // because a silent catch makes an unreachable shelf look like an empty one, and
        // that ambiguity is exactly what made a thin library impossible to explain.
        var albumTracks: [SpotifyTrackDTO] = []
        do {
            albumTracks = try await savedAlbumTrackDTOs(maxAlbums: limits.albums)
            libraryLog.notice("album tracks: \(albumTracks.count, privacy: .public)")
        } catch {
            libraryLog.error("album shelf failed: \(String(describing: error), privacy: .public)")
        }
        dtos += albumTracks

        var playlistTracks: [SpotifyTrackDTO] = []
        if Self.playlistsRestricted {
            // Known refused. Re-probing costs a request and always gets the same answer.
            libraryLog.notice("skipping playlists — Spotify has this app's playlist reads restricted")
        } else {
            do {
                playlistTracks = try await playlistTrackDTOs(
                    maxPlaylists: limits.playlists, maxPerPlaylist: limits.tracksPerPlaylist)
                libraryLog.notice("playlist tracks: \(playlistTracks.count, privacy: .public)")
            } catch {
                libraryLog.error("playlist shelf failed: \(String(describing: error), privacy: .public)")
            }
        }
        dtos += playlistTracks

        let unique = Self.deduplicated(dtos)
        let bpmByID = await bpm(forIDs: unique.compactMap(\.id))
        let result = Self.tracks(from: unique, bpmByID: bpmByID)
        let tagged = result.filter { $0.bpm > 0 }.count
        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))

        libraryLog.notice("library: \(dtos.count, privacy: .public) raw → \(unique.count, privacy: .public) unique → \(result.count, privacy: .public) tracks, \(tagged, privacy: .public) with tempo, in \(seconds, privacy: .public)s")
        if tagged == 0, !result.isEmpty {
            libraryLog.notice("no tempo from Spotify — audio-features is restricted for new apps, so enrichment has to supply it")
        }
        return result
    }

    /// Kept for callers that want only the saved-songs shelf.
    func savedTracks(maxTracks: Int = 5_000) async throws -> [Track] {
        let dtos = try await savedTrackDTOs(max: maxTracks)
        return Self.tracks(from: dtos, bpmByID: await bpm(forIDs: dtos.compactMap(\.id)))
    }

    /// The same song reaches us through several shelves — saved, on its album, and in
    /// three playlists. One `Track` each.
    static func deduplicated(_ dtos: [SpotifyTrackDTO]) -> [SpotifyTrackDTO] {
        var seen = Set<String>()
        return dtos.filter { dto in
            guard let id = dto.id else { return false }
            return seen.insert(id).inserted
        }
    }

    // MARK: - Shelves

    private func savedTrackDTOs(max: Int) async throws -> [SpotifyTrackDTO] {
        var dtos: [SpotifyTrackDTO] = []
        var url: URL? = SpotifyConfig.apiBase
            .appendingPathComponent("me/tracks")
            .appending(queryItems: [URLQueryItem(name: "limit", value: "50")])

        while let next = url, dtos.count < max {
            let page: SpotifySavedTracksPage = try await get(next)
            dtos.append(contentsOf: page.items.map(\.track))
            url = page.next.flatMap(URL.init(string:))
        }
        return dtos
    }

    /// Saved albums. Each page carries its albums' track lists inline, so this costs one
    /// request per 50 albums rather than one per album.
    private func savedAlbumTrackDTOs(maxAlbums: Int) async throws -> [SpotifyTrackDTO] {
        var dtos: [SpotifyTrackDTO] = []
        var albumsSeen = 0
        var url: URL? = SpotifyConfig.apiBase
            .appendingPathComponent("me/albums")
            .appending(queryItems: [URLQueryItem(name: "limit", value: "50")])

        while let next = url, albumsSeen < maxAlbums {
            let page: SpotifySavedAlbumsPage = try await get(next)
            for saved in page.items {
                albumsSeen += 1
                let album = saved.album
                // Album track objects carry no artist of their own, so the album's
                // stands in — otherwise every one of them reads "Unknown".
                dtos += (album.tracks?.items ?? []).map { track in
                    (track.artists?.isEmpty ?? true)
                        ? SpotifyTrackDTO(id: track.id, name: track.name,
                                          artists: [.init(name: album.primaryArtist)],
                                          duration_ms: track.duration_ms)
                        : track
                }
            }
            url = page.next.flatMap(URL.init(string:))
        }
        return dtos
    }

    /// Playlists the runner owns or follows, and the tracks in them.
    ///
    /// This is the expensive shelf — one request per 100 tracks per playlist — so it is
    /// read last and bounded on both axes.
    private func playlistTrackDTOs(maxPlaylists: Int,
                                   maxPerPlaylist: Int) async throws -> [SpotifyTrackDTO] {
        var summaries: [SpotifyPlaylistsPage.PlaylistSummary] = []
        var url: URL? = SpotifyConfig.apiBase
            .appendingPathComponent("me/playlists")
            .appending(queryItems: [URLQueryItem(name: "limit", value: "50")])

        while let next = url, summaries.count < maxPlaylists {
            let page: SpotifyPlaylistsPage = try await get(next)
            summaries += page.items
            url = page.next.flatMap(URL.init(string:))
        }

        // `/me/playlists` returns followed playlists alongside owned ones, and Spotify
        // refuses item reads (403) on its own editorial and algorithmic playlists — the
        // "song radio" ones named after a track. Asking anyway spent a request per
        // playlist to be told no, which then tripped the rate limiter and made even the
        // readable ones fail. Only playlists the runner made are worth asking about.
        let me = try? await profile()
        let owned = summaries.filter { summary in
            guard let ownerID = summary.owner?.id, let meID = me?.id else { return true }
            return ownerID == meID
        }
        libraryLog.notice("playlists: \(summaries.count, privacy: .public) found, \(owned.count, privacy: .public) yours (the rest are followed, and Spotify won't open those)")

        var dtos: [SpotifyTrackDTO] = []
        var failed = 0
        for summary in owned.prefix(maxPlaylists) {
            guard let id = summary.id else { continue }
            do {
                // One playlist failing — deleted, or emptied — must not abandon the rest.
                dtos += try await tracks(inPlaylist: id, max: maxPerPlaylist)
            } catch SpotifyError.http(403, _) {
                // Not this playlist's problem: 403 on a playlist the runner owns is the
                // development-mode restriction, which applies to the endpoint, not the
                // item. Asking the other 139 can only produce 139 more 403s — and doing
                // exactly that is what got the whole app rate-limited for a day. Stop at
                // the first one and record it, so later launches don't re-probe.
                Self.playlistsRestricted = true
                // Not a misconfiguration and not something to apply for: since May 2025
                // Spotify reserves extended Web API access for launched businesses at
                // scale, and the request left the developer dashboard. For an app this
                // size, playlist reads are simply not available.
                libraryLog.notice("playlist reads aren't available to this app (403) — Spotify restricts them to large, launched services. Skipping the playlist shelf for good.")
                return dtos
            } catch SpotifyError.rateLimited(let retryAfter) {
                // Already throttled. Continuing would deepen it.
                libraryLog.notice("rate limited for \(Int(retryAfter), privacy: .public)s — abandoning the playlist shelf")
                return dtos
            } catch {
                failed += 1
                if failed == 1 {
                    libraryLog.error("first playlist failure: \(String(describing: error), privacy: .public)")
                }
                libraryLog.debug("playlist unreadable: \(summary.name, privacy: .private)")
            }
        }
        if failed > 0 {
            libraryLog.notice("\(failed, privacy: .public) of \(owned.count, privacy: .public) playlists unreadable")
        }
        return dtos
    }

    /// Whether Spotify has refused playlist item reads for this app.
    ///
    /// Persisted, because it is a property of the app's API access rather than of this
    /// session: without it every launch re-probes, eats a request, and gets the same
    /// 403. `resetPlaylistRestriction()` clears it, should that access ever change.
    static var playlistsRestricted: Bool {
        get { UserDefaults.standard.bool(forKey: "spotify.playlistsRestricted") }
        set { UserDefaults.standard.set(newValue, forKey: "spotify.playlistsRestricted") }
    }

    static func resetPlaylistRestriction() {
        UserDefaults.standard.set(false, forKey: "spotify.playlistsRestricted")
    }

    private func tracks(inPlaylist id: String, max: Int) async throws -> [SpotifyTrackDTO] {
        var dtos: [SpotifyTrackDTO] = []
        var url: URL? = SpotifyConfig.apiBase
            .appendingPathComponent("playlists/\(id)/tracks")
            .appending(queryItems: [URLQueryItem(name: "limit", value: "100")])

        while let next = url, dtos.count < max {
            let page: SpotifyPlaylistTracksPage = try await get(next)
            // Items can be null: a track pulled from the catalogue, or a local file
            // Spotify cannot serve.
            dtos += page.items.compactMap(\.track)
            url = page.next.flatMap(URL.init(string:))
        }
        return dtos
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

    /// The signed-in account. Cached for the life of this client — it is asked for on
    /// every library read to separate owned playlists from followed ones, and it does
    /// not change mid-session.
    private var cachedProfile: SpotifyProfile?

    func profile() async throws -> SpotifyProfile {
        if let cachedProfile { return cachedProfile }
        let url = SpotifyConfig.apiBase.appendingPathComponent("me")
        let fetched: SpotifyProfile = try await get(url)
        cachedProfile = fetched
        return fetched
    }

    /// The account's Spotify plan, from `GET /me` — "premium", "free", or "open".
    ///
    /// Checked when connecting rather than discovered on the first tap, so a free
    /// account is told up front that Dromo can read its library but can't play it.
    func accountIsPremium() async -> Bool? {
        guard let profile = try? await profile() else { return nil }
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
        let data = try await sendRespectingRateLimit(url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// A GET that waits out a rate limit instead of failing.
    ///
    /// Reading a library is bursty by nature — one request per playlist, per 50 albums,
    /// per 50 saved songs — and a library with 149 playlists exceeds what Spotify will
    /// serve in a window. It answers 429 with a `Retry-After`, and without honouring it
    /// every subsequent request fails too, so one runner's whole playlist shelf comes
    /// back empty and looks like 149 individually broken playlists.
    private func sendRespectingRateLimit(_ url: URL, attempt: Int = 0) async throws -> Data {
        do {
            return try await send(url, method: "GET", body: nil, decodeEmpty: false)
        } catch SpotifyError.rateLimited(let retryAfter) where attempt < 2 && retryAfter <= 5 {
            // Only ride out a brief limit. Capping a long `Retry-After` down to a few
            // seconds and retrying anyway is what turned a transient throttle into a
            // day-long one: Spotify asked for hours, the app waited ten seconds, tried
            // again, and each attempt pushed the window further out. A long wait means
            // stop, not hurry.
            libraryLog.notice("rate limited, waiting \(Int(retryAfter), privacy: .public)s")
            try? await Task.sleep(nanoseconds: UInt64(retryAfter) * 1_000_000_000)
            return try await sendRespectingRateLimit(url, attempt: attempt + 1)
        }
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
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        if code == 429 {
            // Carry Spotify's own back-off so the caller can wait exactly as asked
            // rather than guessing.
            let retryAfter = (http?.value(forHTTPHeaderField: "Retry-After"))
                .flatMap(Double.init) ?? 2
            throw SpotifyError.rateLimited(retryAfter: retryAfter)
        }
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
