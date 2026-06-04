import SwiftUI

/// Sign-in — the app entry. Continuing with Apple Music or Spotify both authenticates
/// the user and connects their music. After this, the music-service connection can be
/// managed from the You tab (`MusicIntegrationsView`).
struct SignInView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            VStack(spacing: Spacing.sm) {
                Text("Dromo")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundColor(.oraTextPrimary)
                Text("Run to the beat. Hit your pace.")
                    .font(.system(size: 16))
                    .foregroundColor(.oraTextSecondary)
            }

            Spacer()

            VStack(spacing: Spacing.md) {
                Text("Sign in to start")
                    .font(.system(size: 13))
                    .foregroundColor(.oraTextMuted)

                MusicProviderButtons()
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.screen)
    }
}
