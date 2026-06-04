import Foundation
import AuthenticationServices
import UIKit

enum OAuthError: LocalizedError {
    case cancelled
    case cannotStart
    var errorDescription: String? {
        switch self {
        case .cancelled:   return "Sign-in was cancelled."
        case .cannotStart: return "Couldn't start the sign-in session."
        }
    }
}

/// Reusable OAuth front door: presents `ASWebAuthenticationSession` and returns
/// the redirect URL. Used by integrations that authenticate via the browser
/// (e.g. Strava). System frameworks only — no third-party SDK.
@MainActor
final class WebAuthenticator {
    private var session: ASWebAuthenticationSession?
    private var anchorProvider: AnchorProvider?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        let anchor = keyWindow() ?? ASPresentationAnchor()
        let provider = AnchorProvider(anchor: anchor)
        self.anchorProvider = provider

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: OAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? OAuthError.cancelled)
                }
            }
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: OAuthError.cannotStart)
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

/// Non-isolated anchor vendor (captures a window fetched on the main actor).
private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}
