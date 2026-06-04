import Foundation
import DromoCore

/// Uploads a completed run to Strava as a GPX activity (Section 6.3).
final class StravaService {
    private let auth: StravaAuthService

    @MainActor
    init(auth: StravaAuthService? = nil) {
        self.auth = auth ?? StravaAuthService()
    }

    var isConfigured: Bool { StravaConfig.isConfigured }

    /// Authorizes if needed, then uploads the session's GPS track. Returns the
    /// Strava upload id.
    func upload(session: Session) async throws -> String {
        let authenticated = await auth.isAuthenticated
        if !authenticated {
            try await auth.authorize()
        }
        let token = try await auth.validAccessToken()
        let gpx = GPXBuilder.build(from: session)

        let boundary = "dromo-\(UUID().uuidString)"
        var request = URLRequest(url: StravaConfig.uploadEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(boundary: boundary, gpx: gpx)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw StravaError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        let upload = try JSONDecoder().decode(StravaUploadResponse.self, from: data)
        return String(upload.id)
    }

    private func multipartBody(boundary: String, gpx: Data) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("data_type", "gpx")
        field("activity_type", "run")
        field("name", "Dromo Run")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"activity.gpx\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/gpx+xml\r\n\r\n".data(using: .utf8)!)
        body.append(gpx)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}

private struct StravaUploadResponse: Codable {
    let id: Int
    let status: String?
    let error: String?
}

/// Builds a GPX 1.1 track from a session's per-second pace log.
enum GPXBuilder {
    static func build(from session: Session) -> Data {
        let formatter = ISO8601DateFormatter()
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Dromo" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>Dromo Run</name><trkseg>
        """
        for log in session.actualPaces where log.latitude != 0 || log.longitude != 0 {
            let time = formatter.string(from: log.timestamp)
            gpx += "<trkpt lat=\"\(log.latitude)\" lon=\"\(log.longitude)\"><time>\(time)</time></trkpt>"
        }
        gpx += "</trkseg></trk></gpx>"
        return Data(gpx.utf8)
    }
}
