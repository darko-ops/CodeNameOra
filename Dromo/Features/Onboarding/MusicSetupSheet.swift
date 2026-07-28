import SwiftUI

/// The music popup shown once, right after sign-in, over the main tabs. Reuses
/// `MusicProviderButtons` (Apple Music / Spotify). Connecting is OPTIONAL: with the
/// catalog stocked, this leads with "start now on Dromo's mixes" and the runner's own
/// library takes over as enrichment tags it. A service can be added later from the
/// You tab (`MusicIntegrationsView`).
struct MusicSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Does this build ship catalog audio? Governs whether we may offer a run before
    /// any provider is connected (see `CatalogLibrary`).
    private var stocked: Bool { CatalogLibrary.shared.isStocked }

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
                Text(stocked ? "Your music, or ours" : "Add your music")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.oraTextPrimary)
                // Only promise the mixes when this build actually ships catalog audio —
                // an unstocked build must not offer a run it can't play.
                Text(stocked
                     ? "Start now with Dromo's running mixes — they're already "
                       + "tempo-tagged. Connect your library whenever you like and "
                       + "your own tracks take over as we match them to your pace."
                     : "Connect a service so Dromo can read your library and match track "
                       + "tempo to your pace. You can do this later from the You tab.")
                    .font(.system(size: 14))
                    .foregroundColor(.oraTextSecondary)
                    .multilineTextAlignment(.center)
            }

            MusicProviderButtons(onConnected: { dismiss() })

            Button(stocked ? "Start with Dromo's mixes" : "Skip for now") { dismiss() }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(stocked ? .zoneSteady : .oraTextSecondary)
                .padding(.top, Spacing.xs)

            Spacer()
        }
        .padding(.horizontal, Spacing.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.oraBackground.ignoresSafeArea())
        .interactiveDismissDisabled(false)
    }
}
