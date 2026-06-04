import SwiftUI
import DromoCore

/// A single track line: artwork, title/artist, and BPM — used inside playlist
/// detail. Tapping it (the enclosing button) plays the track in the Now Playing player.
struct TrackRow: View {
    let track: Track
    var accent: Color = .zoneSteady

    var body: some View {
        HStack(spacing: Spacing.md) {
            TrackArtwork(track: track, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundColor(.oraTextSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(track.bpm))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                    .monospacedDigit()
                Text("BPM")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.oraTextMuted)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
