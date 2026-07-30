import SwiftUI

/// The Apple Music / Spotify connect buttons — shared by the sign-in page and the
/// You-tab music integrations page. Both drive `AppCoordinator.connect`, which ADDS
/// a source to the unified library; an already-connected service's button becomes a
/// library refresh instead of a switch.
struct MusicProviderButtons: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var connecting: AppCoordinator.ProviderChoice?
    @State private var failed = false

    /// Called after a successful connect (e.g. to dismiss the integrations sheet).
    var onConnected: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Apple Music was already white, so it now literally shares the light
            // primary token with every other CTA. Spotify green is a brand colour and
            // is exempt from the muting (spec 1.2).
            button(.appleMusic, system: "applelogo",
                   background: .oraButtonFill, foreground: .oraButtonText)
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
                Text(label(for: choice))
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background)
            .foregroundColor(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(connecting != nil)
    }

    private func isConnected(_ choice: AppCoordinator.ProviderChoice) -> Bool {
        coordinator.sources.contains { $0.choice == choice }
    }

    private func label(for choice: AppCoordinator.ProviderChoice) -> String {
        if connecting == choice { return "Connecting…" }
        if isConnected(choice) { return "Refresh \(choice.rawValue) library" }
        return "Continue with \(choice.rawValue)"
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
