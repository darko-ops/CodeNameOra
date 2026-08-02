import Foundation
import DromoCore

/// `BPMLookup` backed by GetSongBPM (https://getsongbpm.com) — a ~7M-song BPM
/// database queried by artist + title. No audio file or ISRC required, so it works
/// for DRM streaming libraries (Apple Music) the on-device analyzer can't touch.
///
/// Free tier ≈ 200 req/day, ~1 req/sec — the enricher rate-limits accordingly.
struct GetSongBPMClient: BPMLookup {
    let apiKey: String
    var session: URLSession = .shared

    /// The last HTTP status the API answered with, or nil if the request never got
    /// that far.
    ///
    /// `BPMLookup` can only answer `Double?`, so a rejected key, a Cloudflare
    /// challenge and "we don't know that song" all collapse into the same nil — and the
    /// first two are worth knowing about, because no amount of waiting fixes them. The
    /// service records the last outcome so a misconfiguration can be told apart from a
    /// miss instead of being retried forever in silence.
    final class Diagnostics: @unchecked Sendable {
        private let lock = NSLock()
        private var _lastStatus: Int?
        private var _lastBlockedAt: Date?

        var lastStatus: Int? {
            lock.lock(); defer { lock.unlock() }
            return _lastStatus
        }

        /// True when the API refused us rather than simply not knowing the song —
        /// 401/403 (key rejected or bot-challenged) or 429 (over the daily quota).
        var isRefusingRequests: Bool {
            lock.lock(); defer { lock.unlock() }
            guard let status = _lastStatus else { return false }
            return status == 401 || status == 403 || status == 429
        }

        func record(status: Int?) {
            lock.lock(); defer { lock.unlock() }
            _lastStatus = status
            if let status, status == 401 || status == 403 || status == 429 {
                _lastBlockedAt = Date()
            }
        }
    }

    static let diagnostics = Diagnostics()

    func bpm(title: String, artist: String) async -> Double? {
        guard !apiKey.isEmpty else { return nil }
        let lookup = "\(artist) \(title)"
        guard let encoded = lookup.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string:
                "https://api.getsongbpm.com/search/?api_key=\(apiKey)&type=both&lookup=\(encoded)")
        else { return nil }

        guard let (data, response) = try? await session.data(from: url) else {
            Self.diagnostics.record(status: nil)
            return nil
        }
        let status = (response as? HTTPURLResponse)?.statusCode
        Self.diagnostics.record(status: status)
        guard status == 200 else { return nil }
        return Self.parseTempo(from: data)
    }

    /// Extracts the first usable tempo from a GetSongBPM search payload. Tolerant of
    /// the API's quirks: results come under `search` (an array on hits; an error
    /// object on misses, which simply fails to decode → nil).
    static func parseTempo(from data: Data) -> Double? {
        struct Response: Decodable {
            struct Item: Decodable { let tempo: String? }
            let search: [Item]?
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        for item in decoded.search ?? [] {
            if let t = item.tempo, let bpm = Double(t), bpm > 0 { return bpm }
        }
        return nil
    }
}
