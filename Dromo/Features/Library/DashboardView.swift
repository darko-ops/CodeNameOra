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
            tile("MOMENTUM", "\(stats.momentumWeeks)", stats.momentumWeeks == 1 ? "wk streak" : "wk streak", .zonePeak)
            tile("TOTAL", "\(stats.totalUses)", stats.totalUses == 1 ? "run" : "runs", .zoneSteady)
            tile("LISTENS", "\(stats.totalListens)", stats.totalListens == 1 ? "song" : "songs", .zoneWarmUp)
        }
    }

    private func tile(_ label: String, _ value: String, _ unit: String, _ accent: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.oraTextMuted)
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(accent)
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 11))
                .foregroundColor(.oraTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(Color.oraSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Most played

    private var mostPlayed: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("MOST PLAYED")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.oraTextMuted)
            VStack(spacing: 0) {
                ForEach(Array(stats.topTracks.enumerated()), id: \.element.id) { index, track in
                    row(rank: index + 1, track: track)
                    if index < stats.topTracks.count - 1 {
                        Divider().overlay(Color.oraSurfaceElevated)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(Color.oraSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func row(rank: Int, track: TopTrack) -> some View {
        HStack(spacing: Spacing.md) {
            Text("\(rank)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
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
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.zoneSteady)
                .monospacedDigit()
        }
        .padding(.vertical, 8)
    }
}
