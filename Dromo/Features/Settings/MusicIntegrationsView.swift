import SwiftUI

/// Manage the connected music service (You tab). Connect or switch between Apple
/// Music and Spotify after sign-in — the same buttons, surfaced as an integration.
struct MusicIntegrationsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    /// The service a removal is being confirmed for (nil = no prompt showing).
    @State private var removing: AppCoordinator.ProviderChoice?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if !coordinator.sources.isEmpty {
                    sourcesCard
                }

                Text("Connect your music services — Dromo folds every connected library "
                     + "into one, and you can toggle each in or out of the mix anytime.")
                    .font(.system(size: 13))
                    .foregroundColor(.oraTextSecondary)

                MusicProviderButtons()

                // How much of their own library Dromo can pace to today — the bridge
                // from "running on Dromo's mixes" to "running on your music".
                LibraryCoverageCard(library: coordinator.library,
                                    aliases: coordinator.recordingAliases)

                if let email = coordinator.account.currentEmail {
                    Divider().overlay(Color.oraBorder)

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        OraLabel("Signed in as")
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
        .confirmationDialog("Remove \(removing?.rawValue ?? "")?",
                            isPresented: Binding(get: { removing != nil },
                                                 set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let removing { coordinator.disconnect(removing) }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("Its music leaves your mix and you'll sign in again to add it back. "
                 + "What Dromo learned about those songs is kept.")
        }
    }

    /// Every connected service with a toggle: off means "leave my mix for now", not
    /// "disconnect" — auth is retained, and flipping back in is instant.
    private var sourcesCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            OraLabel("Your sources")

            ForEach(coordinator.sources) { source in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: source.isEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(source.isEnabled ? .zoneSteady : .oraTextMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.choice.rawValue)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.oraTextPrimary)
                        Text(source.isEnabled
                             ? "\(source.tracks.count) tracks in the mix"
                             : "Out of the mix — connection kept")
                            .font(.system(size: 12))
                            .foregroundColor(.oraTextMuted)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { source.isEnabled },
                        set: { coordinator.setSource(source.choice, enabled: $0) }))
                        .labelsHidden()
                        .tint(.zoneSteady)

                    // Removing is quieter than the toggle on purpose: the toggle is the
                    // everyday control, and this one costs a re-authorization to undo.
                    // Visible rather than a swipe — this isn't a List, so a swipe
                    // action would render nothing and the only way out would be hidden.
                    Button { removing = source.choice } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(.oraTextMuted)
                    }
                    .accessibilityLabel("Remove \(source.choice.rawValue)")
                }
            }

            // The built-in mixes are the day-one guarantee, not a toggle: they fill
            // whatever cadence the enabled libraries can't reach — but ONLY once the
            // catalog ships with audio. Claiming coverage this build can't play would
            // send a runner into a session with nothing to hear.
            let stocked = CatalogLibrary.shared.isStocked
            HStack(spacing: Spacing.sm) {
                Image(systemName: "waveform")
                    .foregroundColor(stocked ? .zoneSteady : .oraTextMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dromo Mixes")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(stocked ? .oraTextPrimary : .oraTextSecondary)
                    Text(stocked
                         ? "Built in — covers any pace your libraries can't"
                         : "Not in this build yet — your connected libraries carry every run")
                        .font(.system(size: 12))
                        .foregroundColor(.oraTextMuted)
                }
                Spacer()
            }
        }
        .oraCard()
    }
}
