import SwiftUI
import DromoCore

/// Hosts the Dromo demo flow and switches between its screens. The platform-agnostic
/// engine that powers the active session lives in the `DromoCore` package.
struct RootView: View {
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var nowPlaying = NowPlayingController()
    /// Drives the launch reveal — the site's unlock transition, carried over.
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.oraBackground.ignoresSafeArea()

            switch coordinator.screen {
            case .auth:
                AuthView()
                    .transition(.opacity)
            case .setup:
                MainTabView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .session:
                if let session = coordinator.session {
                    ActiveSessionView(session: session)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            case .summary:
                // The `SessionController` route into the summary. Nothing reaches it
                // today — `startSession()` has no callers, and a live run presents the
                // same summary from `LiveHUDView` — but it stays wired so the two paths
                // can't drift, and reads the recorded session rather than the
                // controller, the same as everywhere else.
                if let completed = coordinator.session?.completedSession {
                    PostRunSummaryView(summary: RunSummary(session: completed),
                                       useMetric: true) {
                        coordinator.startOver()
                    }
                    .transition(.opacity)
                }
            }
        }
        // The site's unlock reveal, as the app's launch transition: opacity 0→1,
        // blur 12→0, scale 1.03→1 over ~1.1s. Skipped under Reduce Motion, where a
        // blurring, scaling whole-screen animation is exactly what's being opted out of.
        .opacity(revealed ? 1 : 0)
        .blur(radius: revealed ? 0 : 12)
        .scaleEffect(revealed ? 1 : 1.03)
        .onAppear {
            guard !revealed else { return }
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.easeOut(duration: 1.1)) { revealed = true }
            }
        }
        // Browsing playback routes through the same object the run loop uses, so a
        // Spotify track plays on Spotify. Re-set whenever the connected services change:
        // the router is rebuilt each time, and a stale one would send tracks to a
        // service that is no longer in the mix.
        .onAppear { nowPlaying.router = coordinator.musicProvider }
        .onChange(of: coordinator.sources.map(\.id)) { _ in
            nowPlaying.router = coordinator.musicProvider
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $coordinator.showingLibrary) {
            LibraryView()
        }
        .sheet(isPresented: $coordinator.showingMusicSetup) {
            MusicSetupSheet()
        }
        // Injected last, so these end up the OUTERMOST modifiers. A sheet's content
        // inherits the environment of the view its modifier is attached to, and a
        // modifier chained after .environmentObject is that view's ancestor — so it
        // cannot see the object. With these above the sheets, MusicSetupSheet (which
        // reads the coordinator through MusicProviderButtons) trapped the moment
        // sign-in raised it. Keep new presentation modifiers ABOVE this pair.
        .environmentObject(coordinator)
        .environmentObject(nowPlaying)
    }
}

#Preview {
    RootView()
}
