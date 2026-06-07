import SwiftUI

/// The "Add your music" popup shown once, right after sign-in, over the main tabs.
/// Reuses `MusicProviderButtons` (Apple Music / Spotify). Skippable — the app is
/// usable on the demo catalog without connecting, and a service can be added later
/// from the You tab (`MusicIntegrationsView`).
struct MusicSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Capsule()
                .fill(Color.oraTextMuted.opacity(0.5))
                .frame(width: 40, height: 5)
                .padding(.top, Spacing.sm)

            Spacer()

            Image(systemName: "music.note.list")
                .font(.system(size: 44))
                .foregroundColor(.zoneSteady)

            VStack(spacing: Spacing.sm) {
                Text("Add your music")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.oraTextPrimary)
                Text("Connect a service so Dromo can read your library and match track "
                     + "tempo to your pace. You can do this later from the You tab.")
                    .font(.system(size: 14))
                    .foregroundColor(.oraTextSecondary)
                    .multilineTextAlignment(.center)
            }

            MusicProviderButtons(onConnected: { dismiss() })

            Button("Skip for now") { dismiss() }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.oraTextSecondary)
                .padding(.top, Spacing.xs)

            Spacer()
        }
        .padding(.horizontal, Spacing.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.oraBackground.ignoresSafeArea())
        .interactiveDismissDisabled(false)
    }
}
