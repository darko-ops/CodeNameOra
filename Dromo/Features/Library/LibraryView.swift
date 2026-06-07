import SwiftUI

/// Run history — a list of saved sessions (Section 3, Library). Presented as a
/// sheet; tapping a row opens the detail with its pace/BPM chart.
struct LibraryView: View {
    /// When presented as a sheet, show a "Done" button. As a tab, the tab bar
    /// is the way out, so it's hidden.
    var showsDoneButton = true

    private enum YouTab: String, CaseIterable, Identifiable {
        case momentum = "Momentum", sessions = "Sessions", goals = "Goals"
        var id: String { rawValue }
    }

    @StateObject private var vm = LibraryViewModel()
    @State private var tab: YouTab = .momentum
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.oraBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("", selection: $tab) {
                        ForEach(YouTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Spacing.screen)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xs)

                    switch tab {
                    case .momentum: momentumView
                    case .sessions: sessionsList
                    case .goals: GoalsView()
                    }
                }
            }
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        MusicIntegrationsView()
                    } label: {
                        Image(systemName: "music.note")
                            .foregroundColor(.zoneSteady)
                    }
                    .accessibilityLabel("Music integrations")
                }
                if showsDoneButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .toolbarBackground(Color.oraSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: .dromoSessionSaved)) { _ in
            Task { await vm.load() }
        }
    }

    // MARK: - Momentum (stats dashboard)

    private var momentumView: some View {
        ScrollView {
            DashboardView(stats: vm.stats)
                .padding(.horizontal, Spacing.screen)
                .padding(.vertical, Spacing.md)
        }
    }

    // MARK: - Sessions (recorded run logs)

    private var sessionsList: some View {
        List {
            if vm.summaries.isEmpty {
                Text("No runs yet — finish a run and it'll show up here.")
                    .font(.system(size: 13))
                    .foregroundColor(.oraTextMuted)
                    .listRowBackground(Color.oraSurface)
            } else {
                ForEach(vm.summaries) { summary in
                    ZStack {
                        NavigationLink(destination: LibraryDetailView(summary: summary, vm: vm)) { EmptyView() }
                            .opacity(0)
                        SummaryRow(summary: summary)
                    }
                    .listRowBackground(Color.oraSurface)
                    .listRowSeparatorTint(Color.oraSurfaceElevated)
                }
                .onDelete { indexSet in
                    let ids = indexSet.map { vm.summaries[$0].id }
                    Task { for id in ids { await vm.delete(id) } }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct SummaryRow: View {
    let summary: SessionSummary

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
                Text(String(format: "%.2f km · %@",
                            summary.distanceMeters / 1_000,
                            PaceMath.clock(Double(summary.elapsedSeconds))))
                    .font(.system(size: 12))
                    .foregroundColor(.oraTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(PaceMath.paceString(secondsPerKm: summary.averagePaceSecondsPerKm, metric: true))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.zoneSteady)
                    .monospacedDigit()
                Text("avg pace")
                    .font(.system(size: 10))
                    .foregroundColor(.oraTextMuted)
            }
        }
        .padding(.vertical, 4)
    }

    private var dateText: String {
        summary.startedAt.formatted(date: .abbreviated, time: .shortened)
    }
}
