import SwiftUI
import Charts
import DromoCore

/// Pace + BPM over time on a shared timeline (Section 3, "PaceChartView").
///
/// Both series are normalised to a 0…1 scale and overlaid, with pace labelled on
/// the leading axis and BPM on the trailing axis. Higher = slower pace AND higher
/// BPM, so the two lines rising together visualises the core idea: as you fall
/// behind, Dromo pushes the tempo up. A dashed line marks the target pace.
struct PaceChartView: View {
    let samples: [PaceLog]
    /// Ramped target BPM per tick, aligned 1:1 with `samples`.
    let bpm: [Double]
    let targetPace: Double
    let metric: Bool

    private struct Point: Identifiable {
        let id: Int
        let second: Int
        let pace: Double
        let bpm: Double
    }

    var body: some View {
        let points = makePoints()
        let paceValues = points.map(\.pace) + [targetPace]
        let bpmValues = points.map(\.bpm)
        let paceLo = paceValues.min() ?? 0, paceHi = paceValues.max() ?? 1
        let bpmLo = bpmValues.min() ?? 0, bpmHi = bpmValues.max() ?? 1

        func normPace(_ p: Double) -> Double { normalize(p, paceLo, paceHi) }
        func normBPM(_ b: Double) -> Double { normalize(b, bpmLo, bpmHi) }

        return Chart {
            RuleMark(y: .value("Target", normPace(targetPace)))
                .foregroundStyle(Color.oraTextMuted)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("target")
                        .font(.system(size: 9))
                        .foregroundColor(.oraTextMuted)
                }

            ForEach(points) { p in
                LineMark(x: .value("Time", p.second),
                         y: .value("Value", normPace(p.pace)),
                         series: .value("Series", "Pace"))
                    .foregroundStyle(by: .value("Series", "Pace"))
                    .interpolationMethod(.monotone)

                LineMark(x: .value("Time", p.second),
                         y: .value("Value", normBPM(p.bpm)),
                         series: .value("Series", "BPM"))
                    .foregroundStyle(by: .value("Series", "BPM"))
                    .interpolationMethod(.monotone)
            }
        }
        .chartForegroundStyleScale(["Pace": Color.zoneSteady, "BPM": Color.zonePeak])
        .chartLegend(position: .bottom, spacing: 8)
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                AxisGridLine().foregroundStyle(Color.oraSurfaceElevated)
                AxisValueLabel {
                    if let n = value.as(Double.self) {
                        Text(PaceMath.paceString(secondsPerKm: paceLo + n * (paceHi - paceLo), metric: metric))
                            .font(.system(size: 9))
                            .foregroundColor(.zoneSteady)
                    }
                }
            }
            AxisMarks(position: .trailing, values: [0, 0.5, 1]) { value in
                AxisValueLabel {
                    if let n = value.as(Double.self) {
                        Text("\(Int((bpmLo + n * (bpmHi - bpmLo)).rounded())) BPM")
                            .font(.system(size: 9))
                            .foregroundColor(.zonePeak)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let s = value.as(Int.self) {
                        Text(PaceMath.clock(Double(s)))
                            .font(.system(size: 9))
                            .foregroundColor(.oraTextMuted)
                    }
                }
            }
        }
    }

    private func normalize(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        let span = hi - lo
        guard span > 0 else { return 0.5 }
        return min(1, max(0, (v - lo) / span))
    }

    /// Downsamples to ~150 points so long runs stay smooth.
    private func makePoints() -> [Point] {
        guard !samples.isEmpty else { return [] }
        let maxPoints = 150
        let stride = max(1, samples.count / maxPoints)
        return samples.enumerated().compactMap { index, sample in
            guard index % stride == 0, sample.paceSecondsPerKm > 0 else { return nil }
            let targetBPM = index < bpm.count ? bpm[index] : sample.bpmPlaying
            return Point(id: index, second: index,
                         pace: sample.paceSecondsPerKm, bpm: targetBPM)
        }
    }
}
