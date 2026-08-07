import SwiftUI
import DromoCore

/// Post-run summary: headline stats, the pace+BPM chart, what the run taught Dromo,
/// and export to Strava / Apple Health.
///
/// Driven by the recorded `Session` rather than by a live controller, so it can be shown
/// after any run — which is what finally made it reachable. It previously read its
/// figures off `SessionController`, and nothing constructs one.
struct PostRunSummaryView: View {
    /// The finished run.
    let summary: RunSummary
    /// What each track did to the runner's cadence — the learning half of the summary,
    /// folded in from the sheet this replaces so ending a run tells the whole story in
    /// one place.
    var responses: [TrackResponse] = []
    var trackLabels: [String: String] = [:]
    var useMetric = true
    /// Dismiss. The presenter decides what "done" means — closing a cover, or moving on.
    var onDone: () -> Void

    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var export = ExportViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                header
                statsGrid
                if !summary.samples.isEmpty { chartCard }
                WhatMovedYouCard(responses: responses, labels: trackLabels)
                if !responses.isEmpty { privacyNote }
                exportCard

                Button(action: onDone) {
                    Text("Done")
                }
                .buttonStyle(.lightPrimary)

                Button { coordinator.showingLibrary = true } label: {
                    Label("View history", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.oraTextSecondary)
                }
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, Spacing.lg)
        }
        .background(Color.oraBackground.ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Run complete")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.oraTextPrimary)
            Text("Nice work.")
                .font(.system(size: 14))
                .foregroundColor(.oraTextSecondary)
        }
        .padding(.top, Spacing.md)
    }

    /// Carried over from the sheet this replaces. It sits with "what moved you" because
    /// that is the part that involves learning about the runner, and a claim about where
    /// that stays belongs next to the thing it is about.
    private var privacyNote: some View {
        Text("Dromo learns from this privately, on your phone. Nothing about your run "
             + "leaves the device.")
            .font(.system(size: 11))
            .foregroundColor(.oraTextMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Stats

    private var statsGrid: some View {
        let distance = useMetric
            ? String(format: "%.2f km", summary.distanceMeters / 1_000)
            : String(format: "%.2f mi", summary.distanceMeters / PaceMath.metersPerMile)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                         spacing: Spacing.md) {
            // An indoor run has no distance, and "0.00 km" would be a claim rather than
            // a measurement.
            stat("Distance", summary.distanceMeters > 0 ? distance : "—")
            stat("Time", PaceMath.clock(summary.elapsedSeconds))
            // Avg pace is derived from the run, so it carries the accent; the rest are
            // measured or historical totals and stay primary (rule 1).
            stat("Avg pace",
                 PaceMath.paceString(secondsPerKm: summary.averagePaceSecondsPerKm,
                                     metric: useMetric),
                 color: .zoneSteady)
            stat("Avg off-pace", String(format: "%.0f s/km", summary.averageGap))
            stat("Track changes", "\(summary.trackChanges)")
            stat("BPM range", summary.bpmRangeText ?? "—")
        }
    }

    private func stat(_ title: String, _ value: String,
                      color: Color = .oraTextPrimary) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(color)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.oraTextMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .oraCard(radius: 14, padding: nil)
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            OraLabel("Pace vs BPM")
            PaceChartView(samples: summary.samples,
                          bpm: summary.bpmHistory,
                          targetPace: summary.targetPaceSecondsPerKm,
                          metric: useMetric)
                .frame(height: 180)
        }
        .oraCard()
    }

    // MARK: - Export

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            OraLabel("Export")

            exportRow(
                title: "Strava",
                system: "figure.run",
                status: export.strava,
                subtitle: export.stravaConfigured ? nil : "Add Strava keys to Secrets.xcconfig",
                action: { export.exportToStrava(summary.session) }
            )
            exportRow(
                title: "Apple Health",
                system: "heart.fill",
                status: export.health,
                subtitle: nil,
                action: { export.saveToHealth(summary.session) }
            )
        }
        .oraCard()
    }

    private func exportRow(title: String, system: String,
                           status: ExportViewModel.Status,
                           subtitle: String?,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: system)
                    .foregroundColor(.oraTextPrimary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.oraTextPrimary)
                    if let detail = statusDetail(status) ?? subtitle {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundColor(statusColor(status))
                    }
                }
                Spacer()
                trailing(status)
            }
            .padding(.vertical, Spacing.sm)
        }
        .disabled(status == .working)
    }

    @ViewBuilder
    private func trailing(_ status: ExportViewModel.Status) -> some View {
        switch status {
        case .working: ProgressView().tint(.oraTextSecondary)
        case .done:    Image(systemName: "checkmark.circle.fill").foregroundColor(.oraSuccess)
        case .failed:  Image(systemName: "exclamationmark.circle.fill").foregroundColor(.oraDestructive)
        case .idle:    Image(systemName: "square.and.arrow.up").foregroundColor(.oraTextSecondary)
        }
    }

    private func statusDetail(_ status: ExportViewModel.Status) -> String? {
        switch status {
        case .idle, .working: return nil
        case .done(let m), .failed(let m): return m
        }
    }

    private func statusColor(_ status: ExportViewModel.Status) -> Color {
        switch status {
        case .done:   return .oraSuccess
        case .failed: return .oraDestructive
        default:      return .oraTextMuted
        }
    }
}
