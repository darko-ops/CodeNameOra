import SwiftUI

/// Manage the connected music service (You tab). Connect or switch between Apple
/// Music and Spotify after sign-in — the same buttons, surfaced as an integration.
struct MusicIntegrationsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if !coordinator.providerName.isEmpty {
                    connectedBadge
                }

                Text("Connect a music service so Dromo can read your library and match "
                     + "track tempo to your pace.")
                    .font(.system(size: 13))
                    .foregroundColor(.oraTextSecondary)

                MusicProviderButtons()
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, Spacing.lg)
        }
        .background(Color.oraBackground.ignoresSafeArea())
        .navigationTitle("Music")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.oraSurface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var connectedBadge: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.zoneSteady)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.oraTextMuted)
                Text(coordinator.providerName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
