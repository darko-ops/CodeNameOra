import SwiftUI

/// @main entry point (Section 3).
///
/// Phase 0 scaffold: boots straight into `RootView`. The session/onboarding flow
/// is wired up in later phases.
@main
struct DromoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Segmented controls and nav bars are UIKit underneath, with no SwiftUI hook for
        // their track or selection fills, so the design language is set on the
        // appearance proxies once here rather than per view.
        DromoAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
