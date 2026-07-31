import SwiftUI
import DromoCore

/// A single track line: artwork, title/artist, and BPM — used in playlist detail and in
/// All tracks. Tapping it (the enclosing button) plays the track in the Now Playing player.
struct TrackRow: View {
    let track: Track
    /// Overrides the BPM tint. Left nil, the readout takes its own tempo bucket's ramp
    /// colour, so tempo stays legible while scanning a long list instead of every row
    /// carrying the same accent.
    var accent: Color?

    private var isTagged: Bool { track.bpm > 0 }

    private var bpmColor: Color {
        accent ?? PlaylistCatalog.accent(forBPM: track.bpm) ?? .zoneSteady
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            TrackArtwork(track: track, size: 46, cornerRadius: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    // Untagged titles sit back a step: the row is browsable, but it
                    // can't be placed on the tempo scale yet.
                    .foregroundColor(isTagged ? .oraTextPrimary : .oraTextSecondary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundColor(.oraTextSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if isTagged {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(track.bpm))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(bpmColor)
                        .monospacedDigit()
                    Text("BPM")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.oraTextMuted)
                }
            } else {
                // Shown rather than hidden: the runner knows they own the song, so
                // silently dropping it reads as a bug, not as missing tempo.
                Text("No tempo yet")
                    .font(.system(size: 11))
                    .foregroundColor(.oraTextMuted)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
