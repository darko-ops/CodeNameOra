import SwiftUI
import DromoCore

/// What Dromo has learned about this runner, and the button that erases it.
///
/// Both stores are on-device only and never reach the Global Track Table — they are
/// facts about *this runner's response*, not about the recordings (ARCHITECTURE §5/§8).
/// So deletion is local, immediate, and complete: no server call, nothing to revoke,
/// nothing left behind. The copy says exactly that, because a privacy claim the user
/// can't verify is worth nothing.
@MainActor
final class LearnedDataModel: ObservableObject {

    @Published private(set) var byMode: [PaceMode: Int] = [:]
    @Published private(set) var tasteCount = 0
    @Published private(set) var isLoading = false

    private let effectiveness = GRDBEffectivenessStore()
    private let preferences = GRDBPreferenceStore()

    var totalTracksLearned: Int { byMode.values.reduce(0, +) }
    var hasData: Bool { totalTracksLearned > 0 || tasteCount > 0 }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        var counts: [PaceMode: Int] = [:]
        for mode in PaceMode.allCases {
            counts[mode] = await effectiveness.learned(for: mode).count
        }
        byMode = counts
        tasteCount = await preferences.weights().count
    }

    /// Erase both stores, then re-read so the UI reflects the true state rather than an
    /// assumption that the delete worked.
    func reset() async {
        await effectiveness.reset()
        await preferences.reset()
        await load()
    }
}

struct LearnedDataView: View {
    @StateObject private var model = LearnedDataModel()
    @State private var confirming = false
    @State private var coachEnabled = CoachVoice.isEnabled
    @State private var contributeEnabled = TrackContributor.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("What Dromo has learned")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
                Text("Dromo watches how your cadence responds to each track and uses it "
                     + "to pick better music for you. This stays on your phone — it's "
                     + "never uploaded, and deleting it here deletes it everywhere.")
                    .font(.system(size: 13))
                    .foregroundColor(.oraTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.hasData {
                VStack(spacing: Spacing.sm) {
                    ForEach(PaceMode.allCases, id: \.self) { mode in
                        row(label(for: mode), count: model.byMode[mode] ?? 0)
                    }
                    row("Tracks you rated", count: model.tasteCount)
                }
                .padding(Spacing.md)
                .oraCard(padding: nil)

                Button(role: .destructive) { confirming = true } label: {
                    Text("Reset what Dromo has learned")
                }
                .buttonStyle(.oraDestructive)
                .confirmationDialog("Reset learned data?", isPresented: $confirming,
                                    titleVisibility: .visible) {
                    Button("Reset", role: .destructive) { Task { await model.reset() } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Dromo will start over on what moves you. Your runs and music "
                         + "are untouched. This can't be undone.")
                }
            } else {
                Text("Nothing learned yet — run with music and Dromo will start noticing "
                     + "what moves you.")
                    .font(.system(size: 13))
                    .foregroundColor(.oraTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            coachSection
            contributeSection

            Spacer()
        }
        .padding(Spacing.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.oraBackground.ignoresSafeArea())
        .task { await model.load() }
    }

    /// Phase 7: coaching is additive and opt-in. Named for what it does to the run,
    /// not for the feature, so the trade-off is obvious before turning it on.
    private var coachSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Toggle(isOn: Binding(get: { coachEnabled },
                                 set: { coachEnabled = $0; CoachVoice.isEnabled = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spoken coaching")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.oraTextPrimary)
                    Text("Splits, pace checks and halfway guidance, spoken over your "
                         + "music. The music ducks — it never stops.")
                        .font(.system(size: 12))
                        .foregroundColor(.oraTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(.zoneSteady)
        }
        .padding(Spacing.md)
        .oraCard()
    }

    /// Phase 4: help tag songs for every runner. Shown even while it's unavailable,
    /// with the reason — a toggle that silently does nothing is worse than one that
    /// explains itself.
    private var contributeSection: some View {
        let policy = ContributionPolicy.current
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Toggle(isOn: Binding(get: { contributeEnabled },
                                 set: { contributeEnabled = $0; TrackContributor.isEnabled = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Help tag songs")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(policy.allowsContribution ? .oraTextPrimary : .oraTextSecondary)
                    Text("When you're charging on Wi-Fi, Dromo works out the tempo of "
                         + "songs you own and shares just that number, so other runners "
                         + "with the same song don't have to. Your audio never leaves "
                         + "your phone.")
                        .font(.system(size: 12))
                        .foregroundColor(.oraTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(.zoneSteady)
            .disabled(!policy.allowsContribution)

            if let reason = policy.closedReason {
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundColor(.oraWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.md)
        .oraCard()
    }

    private func label(for mode: PaceMode) -> String {
        switch mode {
        case .push:   return "Tracks measured while behind pace"
        case .hold:   return "Tracks measured while on pace"
        case .settle: return "Tracks measured while ahead"
        }
    }

    private func row(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.oraTextSecondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.oraTextPrimary)
                .monospacedDigit()
        }
    }
}
