import SwiftUI

/// The Apple Music / Spotify connect buttons — shared by the sign-in page (where a
/// selection signs you in) and the You-tab music integrations page (where you can
/// connect or switch services later). Both drive `AppCoordinator.connect`.
struct MusicProviderButtons: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var connecting: AppCoordinator.ProviderChoice?
    @State private var failed = false

    /// Called after a successful connect (e.g. to dismiss the integrations sheet).
    var onConnected: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.md) {
            button(.appleMusic, system: "applelogo", background: .white, foreground: .black)
            button(.spotify, system: "music.note",
                   background: Color(hex: "#1DB954"), foreground: .black)

            if failed {
                Text("Couldn't connect. Tap to try again.")
                    .font(.system(size: 12))
                    .foregroundColor(.oraDestructive)
            }
        }
    }

    private func button(_ choice: AppCoordinator.ProviderChoice,
                        system: String, background: Color, foreground: Color) -> some View {
        Button { connect(choice) } label: {
            HStack(spacing: Spacing.sm) {
                if connecting == choice {
                    ProgressView().tint(foreground)
                } else {
                    Image(systemName: system)
                }
                Text(connecting == choice ? "Connecting…" : "Continue with \(choice.rawValue)")
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background)
            .foregroundColor(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(connecting != nil)
    }

    private func connect(_ choice: AppCoordinator.ProviderChoice) {
        failed = false
        connecting = choice
        Task {
            let ok = await coordinator.connect(choice)
            connecting = nil
            failed = !ok
            if ok { onConnected?() }
        }
    }
}
