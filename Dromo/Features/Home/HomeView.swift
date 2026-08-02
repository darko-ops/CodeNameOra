import SwiftUI

/// Home tab — still a placeholder. Future: dashboard / recent activity / quick-start.
///
/// The one thing it carries is the way out of a dead end: with no music connected there
/// is nothing to pace a run with, and the landing screen said nothing about it. The
/// prompt disappears once a service is connected, so it doesn't become furniture.
struct HomeView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        NavigationStack {
            ZStack {
                Color.oraBackground.ignoresSafeArea()

                VStack(spacing: Spacing.xl) {
                    Spacer()
                    DromoWordmark(size: 22, weight: .bold, color: .oraTextMuted)
                    if coordinator.sources.isEmpty { connectPrompt }
                    Spacer()
                    Spacer()
                }
                .padding(.horizontal, Spacing.screen)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.oraSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var connectPrompt: some View {
        VStack(spacing: Spacing.md) {
            Text("Connect your music and Dromo can start matching songs to your pace.")
                .font(.system(size: 14))
                .foregroundColor(.oraTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink(destination: MusicIntegrationsView()) {
                Text("Connect a music service")
            }
            .buttonStyle(.lightPrimary)
        }
    }
}
