import Foundation
import AuthenticationServices
import UIKit
import KeychainAccess

/// Real Spotify auth using the Authorization Code + PKCE flow.
///
/// Uses `ASWebAuthenticationSession` (system framework) — no Spotify binary SDK
/// is required for sign-in or Web API access. Tokens are persisted in the
/// Keychain and refreshed transparently.
@MainActor
final class SpotifyAuthService: NSObject {

    private let keychain = Keychain(service: "com.daed.dromo.spotify")
    private let tokenKey = "oauth.tokens"
    private var webSession: ASWebAuthenticationSession?
    private var presentationProvider: AuthPresentationProvider?

    var isAuthenticated: Bool { loadTokens() != nil }

    // MARK: - Authorization

    func authorize() async throws {
        guard SpotifyConfig.isConfigured else { throw SpotifyError.notConfigured }

        let verifier = SpotifyPKCE.makeVerifier()
        let challenge = SpotifyPKCE.challenge(for: verifier)
        let state = SpotifyPKCE.makeState()

        var comps = URLComponents(url: SpotifyConfig.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: SpotifyConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: SpotifyConfig.scopes),
            URLQueryItem(name: "state", value: state)
        ]

        let callback = try await presentWebAuth(url: comps.url!)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []

        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw SpotifyError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            let reason = items.first(where: { $0.name == "error" })?.value ?? "no authorization code"
            throw SpotifyError.authFailed(reason)
        }

        try await exchangeCode(code, verifier: verifier)
    }

    func signOut() {
        try? keychain.remove(tokenKey)
    }

    // MARK: - Token access

    /// Returns a valid access token, refreshing it first if needed.
    func validAccessToken() async throws -> String {
        guard var tokens = loadTokens() else { throw SpotifyError.notAuthenticated }
        if tokens.isExpired {
            tokens = try await refresh(tokens)
        }
        return tokens.accessToken
    }

    // MARK: - Token exchange / refresh

    private func exchangeCode(_ code: String, verifier: String) async throws {
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectURI,
            "client_id": SpotifyConfig.clientID,
            "code_verifier": verifier
        ]
        let response = try await postToken(body)
        store(response)
    }

    private func refresh(_ tokens: SpotifyTokens) async throws -> SpotifyTokens {
        guard let refreshToken = tokens.refreshToken else { throw SpotifyError.notAuthenticated }
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": SpotifyConfig.clientID
        ]
        let response = try await postToken(body)
        // Spotify may omit a new refresh token — keep the existing one if so.
        let merged = SpotifyTokenResponse(
            access_token: response.access_token,
            token_type: response.token_type,
            expires_in: response.expires_in,
            refresh_token: response.refresh_token ?? refreshToken,
            scope: response.scope
        )
        store(merged)
        return loadTokens()!
    }

    private func postToken(_ fields: [String: String]) async throws -> SpotifyTokenResponse {
        var request = URLRequest(url: SpotifyConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw SpotifyError.http(code, String(data: data, encoding: .utf8) ?? "token error")
        }
        return try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
    }

    // MARK: - Keychain

    private func loadTokens() -> SpotifyTokens? {
        guard let data = try? keychain.getData(tokenKey) else { return nil }
        return try? JSONDecoder().decode(SpotifyTokens.self, from: data)
    }

    private func store(_ response: SpotifyTokenResponse) {
        let tokens = SpotifyTokens(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: Date().addingTimeInterval(response.expires_in)
        )
        if let data = try? JSONEncoder().encode(tokens) {
            try? keychain.set(data, key: tokenKey)
        }
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - ASWebAuthenticationSession

    private func presentWebAuth(url: URL) async throws -> URL {
        // Capture the presentation anchor on the main actor up front, so the
        // (nonisolated) context-provider callback just returns a stored window.
        let anchor = keyWindow() ?? ASPresentationAnchor()
        let provider = AuthPresentationProvider(anchor: anchor)
        self.presentationProvider = provider

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: SpotifyConfig.callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: SpotifyError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? SpotifyError.cancelled)
                }
            }
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            self.webSession = session
            if !session.start() {
                continuation.resume(throwing: SpotifyError.cannotStartSession)
            }
        }
    }

    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

/// Standalone (non-isolated) presentation-context provider that simply vends a
/// window captured on the main actor — keeps `ASWebAuthenticationSession` happy
/// without forcing main-actor access inside its synchronous callback.
private final class AuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}
