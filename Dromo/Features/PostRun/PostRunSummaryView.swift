import SwiftUI
import DromoCore

/// Step 4 — post-run summary: headline stats, the pace+BPM chart, and export to
/// Strava / Apple Health.
struct PostRunSummaryView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject var session: SessionController
    @StateObject private var export = ExportViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                header
                statsGrid
                chartCard
                exportCard

                Button { coordinator.startOver() } label: {
                    Text("New run")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.zoneSteady)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button { coordinator.showingLibrary = true } label: {
                    Label("View history", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.oraTextSecondary)
                }
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, Spacing.lg)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Run complete")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.oraTextPrimary)
            Text("Nice work.")
                .font(.system(size: 14))
                .foregroundColor(.oraTextSecondary)
        }
        .padding(.top, Spacing.md)
    }

    // MARK: - Stats

    private var statsGrid: some View {
        let metric = session.settings.useMetric
        let distance = metric
            ? String(format: "%.2f km", session.distanceMeters / 1_000)
            : String(format: "%.2f mi", session.distanceMeters / PaceMath.metersPerMile)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                         spacing: Spacing.md) {
            stat("Distance", distance)
            stat("Time", PaceMath.clock(session.elapsedSeconds))
            stat("Avg pace", PaceMath.paceString(secondsPerKm: session.averagePaceSecondsPerKm, metric: metric))
            stat("Avg off-pace", String(format: "%.0f s/km", session.averageGap))
            stat("Track changes", "\(session.trackChanges)")
            stat("BPM range", bpmRangeText)
        }
    }

    private var bpmRangeText: String {
        guard let lo = session.bpmHistory.min(), let hi = session.bpmHistory.max() else { return "—" }
        return "\(Int(lo))–\(Int(hi))"
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.oraTextPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.oraTextMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("PACE vs BPM")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.oraTextMuted)
            PaceChartView(samples: session.samples,
                          bpm: session.bpmHistory,
                          targetPace: session.targetPaceSecondsPerKm,
                          metric: session.settings.useMetric)
                .frame(height: 180)
        }
        .padding(Spacing.md)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Export

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("EXPORT")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.oraTextMuted)

            exportRow(
                title: "Strava",
                system: "figure.run",
                status: export.strava,
                subtitle: export.stravaConfigured ? nil : "Add Strava keys to Secrets.xcconfig",
                action: { export.exportToStrava(session.completedSession) }
            )
            exportRow(
                title: "Apple Health",
                system: "heart.fill",
                status: export.health,
                subtitle: nil,
                action: { export.saveToHealth(session.completedSession) }
            )
        }
        .padding(Spacing.md)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
