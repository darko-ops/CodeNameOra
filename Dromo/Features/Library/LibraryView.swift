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

    @EnvironmentObject private var coordinator: AppCoordinator
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
                            .foregroundColor(.oraTextSecondary)
                    }
                    .accessibilityLabel("Music integrations")
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        LearnedDataView()
                    } label: {
                        Image(systemName: "brain")
                            .foregroundColor(.oraTextSecondary)
                    }
                    .accessibilityLabel("What Dromo has learned")
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
            VStack(spacing: Spacing.xl) {
                DashboardView(stats: vm.stats)
                setupSection
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, Spacing.md)
        }
    }

    // MARK: - Setup

    /// Named rows for the things the You tab actually leads to.
    ///
    /// These were reachable only through two unlabelled glyphs in the leading toolbar —
    /// where iOS puts the back button — so connecting a music service, the thing a new
    /// runner most needs to do, was effectively hidden. The toolbar shortcuts stay for
    /// the other sub-tabs; this is the discoverable path.
    private var setupSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            OraLabel("Setup")

            VStack(spacing: 0) {
                NavigationLink(destination: MusicIntegrationsView()) {
                    row(icon: "music.note",
                        title: "Music services",
                        detail: musicDetail,
                        // The one row that can be in an unfinished state, so it says so:
                        // an empty library is the difference between a working app and
                        // one that silently has nothing to play.
                        highlight: coordinator.sources.isEmpty)
                }
                .buttonStyle(.plain)

                Divider()
                    .overlay(Color.oraSurfaceElevated)
                    .padding(.leading, Spacing.md + 34 + Spacing.md)

                NavigationLink(destination: LearnedDataView()) {
                    row(icon: "brain",
                        title: "What Dromo has learned",
                        detail: "Your taste, and what it does with it",
                        highlight: false)
                }
                .buttonStyle(.plain)
            }
            .oraCard(padding: nil)
        }
    }

    /// Says what's connected, so the row answers the question rather than only leading
    /// somewhere that answers it.
    private var musicDetail: String {
        let connected = coordinator.sources.map(\.choice.rawValue)
        guard !connected.isEmpty else { return "Nothing connected yet" }
        return connected.joined(separator: " · ")
    }

    private func row(icon: String, title: String, detail: String,
                     highlight: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.oraSurfaceElevated)
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(highlight ? .zoneSteady : .oraTextSecondary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(highlight ? .zoneSteady : .oraTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.oraTextMuted)
        }
        .padding(Spacing.md)
        .contentShape(Rectangle())
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
                    .listRowSeparatorTint(Color.oraBorder)
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
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.zoneSteady)
                    .monospacedDigit()
                OraLabel("avg pace")
            }
        }
        .padding(.vertical, 4)
    }

    private var dateText: String {
        summary.startedAt.formatted(date: .abbreviated, time: .shortened)
    }
}
