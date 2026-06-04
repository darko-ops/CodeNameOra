import SwiftUI

/// @main entry point (Section 3).
///
/// Phase 0 scaffold: boots straight into `RootView`. The session/onboarding flow
/// is wired up in later phases.
@main
struct DromoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
