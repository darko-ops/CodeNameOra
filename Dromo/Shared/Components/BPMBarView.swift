import SwiftUI

/// Horizontal gauge showing where the live target BPM sits within the user's
/// BPM range. The marker slides up as Dromo pushes and down as it eases.
struct BPMBarView: View {
    let targetBPM: Double
    let range: ClosedRange<Double>
    let color: Color

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (targetBPM - range.lowerBound) / span))
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("TARGET BPM")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.oraTextMuted)
                Spacer()
                Text("\(Int(targetBPM))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.oraSurfaceElevated)
                    Capsule()
                        .fill(color)
                        .frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
            .animation(.easeInOut(duration: 0.5), value: fraction)
        }
    }
}
