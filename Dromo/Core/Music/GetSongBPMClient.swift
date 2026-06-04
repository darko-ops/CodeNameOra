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

    func bpm(title: String, artist: String) async -> Double? {
        guard !apiKey.isEmpty else { return nil }
        let lookup = "\(artist) \(title)"
        guard let encoded = lookup.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string:
                "https://api.getsongbpm.com/search/?api_key=\(apiKey)&type=both&lookup=\(encoded)")
        else { return nil }

        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
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
