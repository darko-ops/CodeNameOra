import SwiftUI

@MainActor
final class GoalsViewModel: ObservableObject {
    @Published var goals = WeeklyGoals()
    @Published private(set) var progress = WeekProgress()
    private let repo = GoalsRepository()

    func load() async {
        goals = await repo.load()
        progress = await repo.weekProgress()
    }

    func persist() async {
        await repo.save(goals)
        progress = await repo.weekProgress()
    }
}

/// You → Goals: set weekly targets and see this week's progress against them.
struct GoalsView: View {
    @StateObject private var vm = GoalsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                sessionsCard
                distanceCard
                Text("Goals reset each week. Progress reflects recorded sessions.")
                    .font(.system(size: 12))
                    .foregroundColor(.oraTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, Spacing.lg)
        }
        .background(Color.oraBackground.ignoresSafeArea())
        .task { await vm.load() }
    }

    // MARK: Cards

    private var sessionsCard: some View {
        goalCard(
            title: "Weekly runs",
            valueText: "\(vm.goals.weeklySessions)",
            unit: "runs / week",
            done: Double(vm.progress.sessions),
            target: Double(vm.goals.weeklySessions),
            progressText: "\(vm.progress.sessions) / \(vm.goals.weeklySessions) this week",
            accent: .zoneSteady,
            stepper: AnyView(
                Stepper("", value: $vm.goals.weeklySessions, in: 1...14)
                    .labelsHidden()
                    .onChange(of: vm.goals.weeklySessions) { _ in Task { await vm.persist() } }
            ))
    }

    private var distanceCard: some View {
        goalCard(
            title: "Weekly distance",
            valueText: String(format: "%.0f", vm.goals.weeklyDistanceKm),
            unit: "km / week",
            done: vm.progress.distanceKm,
            target: vm.goals.weeklyDistanceKm,
            progressText: String(format: "%.1f / %.0f km this week",
                                 vm.progress.distanceKm, vm.goals.weeklyDistanceKm),
            accent: .zoneWarmUp,
            stepper: AnyView(
                Stepper("", value: $vm.goals.weeklyDistanceKm, in: 5...100, step: 5)
                    .labelsHidden()
                    .onChange(of: vm.goals.weeklyDistanceKm) { _ in Task { await vm.persist() } }
            ))
    }

    private func goalCard(title: String, valueText: String, unit: String,
                          done: Double, target: Double, progressText: String,
                          accent: Color, stepper: AnyView) -> some View {
        let fraction = target > 0 ? min(1, max(0, done / target)) : 0
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.oraTextMuted)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(valueText)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.oraTextPrimary)
                            .monospacedDigit()
                        Text(unit)
                            .font(.system(size: 12))
                            .foregroundColor(.oraTextSecondary)
                    }
                }
                Spacer()
                stepper
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.oraSurfaceElevated)
                    Capsule().fill(accent).frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
            .animation(.easeInOut(duration: 0.3), value: fraction)

            Text(progressText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(fraction >= 1 ? accent : .oraTextSecondary)
        }
        .padding(Spacing.md)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
