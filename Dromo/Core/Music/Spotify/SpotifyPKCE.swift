import Foundation
import CryptoKit

/// PKCE (Proof Key for Code Exchange) helpers for Spotify's Authorization Code
/// + PKCE flow — the recommended flow for mobile apps with no client secret.
enum SpotifyPKCE {

    /// A high-entropy `code_verifier` (43–128 chars, base64url).
    static func makeVerifier() -> String {
        base64url(randomData(count: 64))
    }

    /// `code_challenge = base64url(SHA256(code_verifier))`.
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64url(Data(digest))
    }

    /// Opaque `state` value to defend against CSRF.
    static func makeState() -> String {
        base64url(randomData(count: 16))
    }

    private static func randomData(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
