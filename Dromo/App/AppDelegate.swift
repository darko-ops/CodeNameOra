import UIKit

/// UIApplicationDelegate hooks (Section 3).
///
/// Phase 0 scaffold: no-op. Push registration, RevenueCat/Sentry/PostHog
/// bootstrapping, and audio-session priming are wired up in later phases.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // TODO(Phase 5/6): configure RevenueCat, Sentry, PostHog here.
        return true
    }
}
