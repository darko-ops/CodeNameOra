import SwiftUI
import DromoCore

/// Hosts the Dromo demo flow and switches between its screens. The platform-agnostic
/// engine that powers the active session lives in the `DromoCore` package.
struct RootView: View {
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var nowPlaying = NowPlayingController()

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
                if let session = coordinator.session {
                    PostRunSummaryView(session: session)
                        .transition(.opacity)
                }
            }
        }
        .environmentObject(coordinator)
        .environmentObject(nowPlaying)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $coordinator.showingLibrary) {
            LibraryView()
        }
        .sheet(isPresented: $coordinator.showingMusicSetup) {
            MusicSetupSheet()
        }
    }
}

#Preview {
    RootView()
}
