import SwiftUI
import DromoCore

/// Detail for a saved run: headline stats + the pace/BPM chart, reconstructed
/// from the persisted per-second pace log.
struct LibraryDetailView: View {
    let summary: SessionSummary
    @ObservedObject var vm: LibraryViewModel
    @State private var session: Session?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                statsGrid
                chartCard
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, Spacing.lg)
        }
        .background(Color.oraBackground.ignoresSafeArea())
        .navigationTitle(summary.startedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.oraSurface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { session = await vm.fullSession(summary.id) }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
            stat("Distance", String(format: "%.2f km", summary.distanceMeters / 1_000))
            stat("Time", PaceMath.clock(Double(summary.elapsedSeconds)))
            stat("Avg pace", PaceMath.paceString(secondsPerKm: summary.averagePaceSecondsPerKm, metric: true))
            stat("Target", PaceMath.paceString(secondsPerKm: summary.targetPace, metric: true))
        }
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

    @ViewBuilder
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("PACE vs BPM")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.oraTextMuted)
            if let session, !session.actualPaces.isEmpty {
                PaceChartView(samples: session.actualPaces, bpm: [],
                              targetPace: summary.targetPace, metric: true)
                    .frame(height: 180)
            } else {
                Text("No detailed data for this run.")
                    .font(.system(size: 12))
                    .foregroundColor(.oraTextMuted)
                    .frame(height: 80)
            }
        }
        .padding(Spacing.md)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
