import Foundation
import KeychainAccess

/// Strava configuration (Section 6.3). Strava's token exchange requires the
/// client secret (it does not support secret-less PKCE), so both are read from
/// Secrets.xcconfig.
enum StravaConfig {
    static var clientID: String { Config.stravaClientID }
    static var clientSecret: String { Config.stravaClientSecret }
    static let redirectURI = "dromo://strava-callback"
    static let callbackScheme = "dromo"
    static let scope = "activity:write"

    static let authorizeEndpoint = URL(string: "https://www.strava.com/oauth/mobile/authorize")!
    static let tokenEndpoint = URL(string: "https://www.strava.com/oauth/token")!
    static let uploadEndpoint = URL(string: "https://www.strava.com/api/v3/uploads")!

    static var isConfigured: Bool { !clientID.isEmpty && !clientSecret.isEmpty }
}

enum StravaError: LocalizedError {
    case notConfigured, notAuthenticated, authFailed(String), http(Int, String)
    var errorDescription: String? {
        switch self {
        case .notConfigured:  return "Add STRAVA_CLIENT_ID / STRAVA_CLIENT_SECRET to Secrets.xcconfig."
        case .notAuthenticated: return "Not connected to Strava."
        case .authFailed(let m): return "Strava authorization failed: \(m)."
        case .http(let c, let m): return "Strava error \(c): \(m)."
        }
    }
}

private struct StravaTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

private struct StravaTokenResponse: Codable {
    let access_token: String
    let refresh_token: String
    let expires_at: Double      // absolute unix time
}

/// Strava OAuth (Authorization Code) via the browser, with Keychain-persisted
/// tokens and transparent refresh.
@MainActor
final class StravaAuthService {
    private let keychain = Keychain(service: "com.daed.dromo.strava")
    private let tokenKey = "oauth.tokens"
    private let web = WebAuthenticator()

    var isAuthenticated: Bool { loadTokens() != nil }

    func authorize() async throws {
        guard StravaConfig.isConfigured else { throw StravaError.notConfigured }

        var comps = URLComponents(url: StravaConfig.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: StravaConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: StravaConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: StravaConfig.scope)
        ]

        let callback = try await web.authenticate(url: comps.url!, callbackScheme: StravaConfig.callbackScheme)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw StravaError.authFailed(items.first(where: { $0.name == "error" })?.value ?? "no code")
        }
        try await exchange(code: code)
    }

    func validAccessToken() async throws -> String {
        guard var tokens = loadTokens() else { throw StravaError.notAuthenticated }
        if tokens.isExpired { tokens = try await refresh(tokens) }
        return tokens.accessToken
    }

    func signOut() { try? keychain.remove(tokenKey) }

    // MARK: - Token exchange / refresh

    private func exchange(code: String) async throws {
        try store(await postToken([
            "client_id": StravaConfig.clientID,
            "client_secret": StravaConfig.clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ]))
    }

    private func refresh(_ tokens: StravaTokens) async throws -> StravaTokens {
        try store(await postToken([
            "client_id": StravaConfig.clientID,
            "client_secret": StravaConfig.clientSecret,
            "refresh_token": tokens.refreshToken,
            "grant_type": "refresh_token"
        ]))
        return loadTokens()!
    }

    private func postToken(_ fields: [String: String]) async throws -> StravaTokenResponse {
        var request = URLRequest(url: StravaConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw StravaError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(StravaTokenResponse.self, from: data)
    }

    // MARK: - Keychain

    private func loadTokens() -> StravaTokens? {
        guard let data = try? keychain.getData(tokenKey) else { return nil }
        return try? JSONDecoder().decode(StravaTokens.self, from: data)
    }

    @discardableResult
    private func store(_ response: StravaTokenResponse) -> StravaTokenResponse {
        let tokens = StravaTokens(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: Date(timeIntervalSince1970: response.expires_at)
        )
        if let data = try? JSONEncoder().encode(tokens) {
            try? keychain.set(data, key: tokenKey)
        }
        return response
    }
}
