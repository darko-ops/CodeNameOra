import SwiftUI
import DromoCore

/// Shown when a live run ends and there is something true to say about it. The run is
/// already saved by `LiveRunRecorder` — this sheet exists purely to close the loop the
/// learning opened, so the runner sees what Dromo noticed rather than trusting that
/// something happened invisibly.
struct LiveRunSummarySheet: View {
    let responses: [TrackResponse]
    let labels: [String: String]
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nice run")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.oraTextPrimary)
                    Text("Here's what Dromo measured while you ran.")
                        .font(.system(size: 13))
                        .foregroundColor(.oraTextSecondary)
                }

                WhatMovedYouCard(responses: responses, labels: labels)

                Text("Dromo learns from this privately, on your phone. Nothing about "
                     + "your run leaves the device.")
                    .font(.system(size: 11))
                    .foregroundColor(.oraTextMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.zoneSteady)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(Spacing.screen)
        }
        .background(Color.oraBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
