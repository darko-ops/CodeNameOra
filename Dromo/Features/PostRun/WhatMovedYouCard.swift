import SwiftUI
import DromoCore

/// "What moved you" — the post-run section that makes the learning visible.
///
/// It reports what was measured during each track's play window and nothing more.
/// Dromo cannot know that a song caused a cadence change (hills and traffic lights
/// don't sign their work), so the copy stays at "your cadence came up 6 spm while this
/// played". A runner who catches the app overclaiming once will discount everything
/// else it says, including the parts that are exactly right.
///
/// Hidden entirely when the run was too short to attribute — an empty box that says
/// "no data" is worse than no box.
struct WhatMovedYouCard: View {

    let responses: [TrackResponse]
    /// trackID → "Title — Artist", supplied by the session (catalog ids included).
    let labels: [String: String]

    private var highlights: [RunHighlight] { RunHighlights.from(responses) }
    private var drag: RunHighlight? { RunHighlights.drag(responses) }

    var body: some View {
        if !highlights.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WHAT MOVED YOU")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.oraTextMuted)
                    Text("Measured while each track played")
                        .font(.system(size: 11))
                        .foregroundColor(.oraTextMuted)
                }

                ForEach(Array(highlights.enumerated()), id: \.offset) { _, highlight in
                    row(highlight, tint: .zoneSteady)
                }

                if let drag {
                    Divider().overlay(Color.oraTextMuted.opacity(0.25))
                    row(drag, tint: .zonePeak)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.oraSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func row(_ highlight: RunHighlight, tint: Color) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: highlight.helped ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(labels[highlight.trackID] ?? highlight.trackID)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.oraTextPrimary)
                    .lineLimit(1)
                Text("\(highlight.headline) \(highlight.context).")
                    .font(.system(size: 12))
                    .foregroundColor(.oraTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    WhatMovedYouCard(
        responses: [
            TrackResponse(trackID: "1", mode: .push, reward: 6.2, samples: 120),
            TrackResponse(trackID: "2", mode: .hold, reward: 1.4, samples: 95),
            TrackResponse(trackID: "3", mode: .push, reward: -5.5, samples: 140),
        ],
        labels: ["1": "Midnight City — M83",
                 "2": "Instant Crush — Daft Punk",
                 "3": "Weightless — Marconi Union"])
    .padding()
    .background(Color.oraBackground)
}
