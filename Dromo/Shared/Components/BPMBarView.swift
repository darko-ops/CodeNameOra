import SwiftUI

/// Horizontal gauge showing where the live target BPM sits within the runner's BPM
/// range. The fill slides up as Dromo pushes and down as it eases.
///
/// Design language v2: the fill is a gradient from `zoneWarmUp` into the current zone
/// colour rather than a flat bar, and live cadence gets its own tick — so the bar shows
/// both where the music is being aimed and where the runner actually is.
struct BPMBarView: View {
    let targetBPM: Double
    let range: ClosedRange<Double>
    /// The current zone colour; the gradient's far end.
    let color: Color
    /// Live cadence, marked by a tick. Nil hides the tick.
    var cadence: Double?
    /// Behind pace — the label gains an arrow, since the bar is being driven upward.
    var isPushing: Bool = false

    private func fraction(_ value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    private var targetFraction: Double { fraction(targetBPM) }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                OraLabel(isPushing ? "Target BPM ↑" : "Target BPM")
                Spacer()
                Text("\(Int(targetBPM))")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.oraSurfaceElevated)

                    Capsule()
                        .fill(LinearGradient(colors: [.zoneWarmUp, color],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, geo.size.width * targetFraction))

                    // Live cadence, so the runner can see stride against the target the
                    // music is chasing. Clamped inside the track so it never half-hangs
                    // off either end.
                    if let cadence {
                        let x = geo.size.width * fraction(cadence)
                        Capsule()
                            .fill(Color.oraTextPrimary)
                            .frame(width: 3)
                            .offset(x: min(max(x - 1.5, 0), geo.size.width - 3))
                    }
                }
            }
            .frame(height: 10)
            .animation(.easeInOut(duration: 0.5), value: targetFraction)

            HStack {
                Text("\(Int(range.lowerBound))")
                Spacer()
                Text("\(Int(range.upperBound))")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.oraTextMuted)
            .monospacedDigit()
        }
    }
}

#Preview {
    VStack(spacing: Spacing.xl) {
        BPMBarView(targetBPM: 168, range: 148...188, color: .zoneSteady, cadence: 166)
        BPMBarView(targetBPM: 182, range: 148...188, color: .zonePeak, cadence: 160,
                   isPushing: true)
    }
    .padding()
    .background(Color.oraBackground)
}
