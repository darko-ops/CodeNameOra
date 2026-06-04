import Foundation
import DromoCore

/// URLSession implementation of `TrackTableAPI` against the Phase-1 server.
/// Sends only identity keys + numeric `AnalysisResult` — no audio, no titles (§4).
struct HTTPTrackTableClient: TrackTableAPI {
    let baseURL: URL
    var session: URLSession = .shared

    private var encoder: JSONEncoder { JSONEncoder() }
    private var decoder: JSONDecoder { JSONDecoder() }

    // MARK: GET /v1/track

    func lookup(_ key: IdentityKey) async throws -> TrackFacts? {
        var comps = URLComponents(url: baseURL.appendingPathComponent("v1/track"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            key.isrc.map { URLQueryItem(name: "isrc", value: $0) },
            key.fingerprint.map { URLQueryItem(name: "fingerprint", value: $0) },
        ].compactMap { $0 }

        let (data, response) = try await session.data(from: comps.url!)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return nil }
        guard code == 200 else { throw URLError(.badServerResponse) }
        return try decoder.decode(TrackFacts.self, from: data)
    }

    // MARK: POST /v1/track/batch

    func batchLookup(_ keys: [IdentityKey]) async throws -> [BatchResult] {
        struct Body: Encodable { let keys: [IdentityKey] }
        struct Item: Decodable { let key: IdentityKey; let hit: Bool; let track: TrackFacts? }
        struct Resp: Decodable { let results: [Item] }

        let data = try await post(path: "v1/track/batch", body: Body(keys: keys))
        let resp = try decoder.decode(Resp.self, from: data)
        return resp.results.map { BatchResult(key: $0.key, facts: $0.track) }
    }

    // MARK: POST /v1/track

    func populate(_ result: AnalysisResult) async throws -> TrackFacts {
        struct Resp: Decodable { let created: Bool; let track: TrackFacts }
        let data = try await post(path: "v1/track", body: result)
        return try decoder.decode(Resp.self, from: data).track
    }

    // MARK: POST /v1/track/{id}/confirm

    func confirm(trackID: String, signal: ObjectiveSignal,
                 clientID: String) async throws -> TrackFacts? {
        struct Body: Encodable {
            let client_id: String
            let signal: String
            let observed_bpm: Double?
        }
        let body = Body(client_id: clientID, signal: signal.serverSignal,
                        observed_bpm: signal.observedBPM)
        let data = try await post(path: "v1/track/\(trackID)/confirm", body: body)
        return try decoder.decode(TrackFacts.self, from: data)
    }

    // MARK: -

    private func post<T: Encodable>(path: String, body: T) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw URLError(.badServerResponse) }
        return data
    }
}
