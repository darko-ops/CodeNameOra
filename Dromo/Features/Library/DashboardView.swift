import SwiftUI

/// The "You" dashboard: momentum / total / listens tiles + a most-played ranking.
struct DashboardView: View {
    let stats: DashboardStats

    var body: some View {
        VStack(spacing: Spacing.md) {
            tiles
            if !stats.topTracks.isEmpty { mostPlayed }
        }
    }

    // MARK: Stat tiles

    private var tiles: some View {
        HStack(spacing: Spacing.md) {
            tile("Momentum", "\(stats.momentumWeeks)", "wk streak")
            tile("Total", "\(stats.totalUses)", stats.totalUses == 1 ? "run" : "runs")
            tile("Listens", "\(stats.totalListens)", stats.totalListens == 1 ? "song" : "songs")
        }
    }

    private func tile(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 4) {
            OraLabel(label)
            // Historical totals, so primary rather than accent (rule 1).
            Text(value)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.oraTextPrimary)
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 11))
                .foregroundColor(.oraTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .oraCard(padding: nil)
    }

    // MARK: Most played

    private var mostPlayed: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            OraLabel("Most played")
            VStack(spacing: 0) {
                ForEach(Array(stats.topTracks.enumerated()), id: \.element.id) { index, track in
                    row(rank: index + 1, track: track)
                    if index < stats.topTracks.count - 1 {
                        Divider().overlay(Color.oraBorder)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .oraCard(padding: nil)
        }
    }

    private func row(rank: Int, track: TopTrack) -> some View {
        HStack(spacing: Spacing.md) {
            Text("\(rank)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.oraTextMuted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.oraTextSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(track.plays)×")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.zoneSteady)
                .monospacedDigit()
        }
        .padding(.vertical, 8)
    }
}
