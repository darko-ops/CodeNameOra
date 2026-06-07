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

                if let email = coordinator.account.currentEmail {
                    Divider().overlay(Color.oraTextMuted.opacity(0.3))

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Signed in as")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.oraTextMuted)
                        Text(email)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.oraTextPrimary)

                        Button(role: .destructive) {
                            coordinator.signOut()
                        } label: {
                            Text("Sign Out")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.oraDestructive)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.oraSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.top, Spacing.xs)
                    }
                }
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
