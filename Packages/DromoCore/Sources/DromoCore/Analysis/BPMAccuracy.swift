import Foundation

/// One ground-truth measurement: a track's independently-established true BPM vs.
/// what the on-device pipeline detected (Phase 7). `trueBPM` must NOT come from the
/// engine under test — that would be circular.
public struct GroundTruthResult: Sendable, Equatable {
    public let trackID: String
    public let trueBPM: Double
    public let difficulty: String
    public let detectedBPM: Double
    public let confidence: Double
    public let octaveFlag: AnalysisResult.OctaveFlag
    public let analysisMs: Int?

    public init(trackID: String, trueBPM: Double, difficulty: String,
                detectedBPM: Double, confidence: Double,
                octaveFlag: AnalysisResult.OctaveFlag, analysisMs: Int? = nil) {
        self.trackID = trackID
        self.trueBPM = trueBPM
        self.difficulty = difficulty
        self.detectedBPM = detectedBPM
        self.confidence = confidence
        self.octaveFlag = octaveFlag
        self.analysisMs = analysisMs
    }
}

/// The GREEN/YELLOW/RED thresholds — stated BEFORE measuring so the verdict is
/// honest (Phase 7 requirement). Defaults are the spec's suggested starting bar.
public struct AccuracyBar: Sendable {
    public var exactToleranceBPM = 1.0      // "exact" match window
    public var matchToleranceBPM = 2.0      // octave-corrected match window
    public var highConfidenceThreshold = 0.5
    public var greenOctaveMatch = 0.90      // GREEN needs ≥ this octave-corrected match
    public var greenMedianError = 2.0       // …AND median octave-corrected error ≤ this
    public var redOctaveMatch = 0.70        // RED below this octave-corrected match
    public var redHighConfidenceErrorRate = 0.20   // …or high-confidence wrong this often
    public init() {}
}

public enum AccuracyVerdict: String, Sendable {
    case green = "GREEN", yellow = "YELLOW", red = "RED"
}

public struct DifficultyStat: Sendable, Equatable {
    public let count: Int
    public let octaveMatchRate: Double
    public let meanAbsErrorOctaveCorrected: Double
}

/// The Phase-7 deliverable, computed (not eyeballed) from ground-truth results.
public struct BPMAccuracyReport: Sendable {
    public let count: Int
    public let exactMatchRate: Double
    public let octaveCorrectedMatchRate: Double
    public let meanAbsErrorRaw: Double
    public let medianAbsErrorRaw: Double
    public let meanAbsErrorOctaveCorrected: Double
    public let medianAbsErrorOctaveCorrected: Double
    public let byDifficulty: [String: DifficultyStat]
    public let highConfidenceErrorRate: Double
    public let lowConfidenceErrorRate: Double
    /// True when low-confidence readings err more than high-confidence ones — i.e.
    /// confidence is a usable gate.
    public let confidencePredictsError: Bool
    /// Of the cases that were *only* wrong by an octave, how many did `tempo_octave_flag`
    /// actually flag (so the engine could resolve them against cadence)?
    public let octaveFlagRecall: Double
    public let verdict: AccuracyVerdict
}

public enum BPMAccuracy {

    public static func evaluate(_ rows: [GroundTruthResult],
                                bar: AccuracyBar = .init()) -> BPMAccuracyReport {
        let n = rows.count
        let rawErrors = rows.map(rawError)
        let octErrors = rows.map(octaveCorrectedError)

        let exact = rows.filter { rawError($0) <= bar.exactToleranceBPM }.count
        let octMatch = rows.filter { octaveCorrectedError($0) <= bar.matchToleranceBPM }.count
        let octMatchRate = n == 0 ? 0 : Double(octMatch) / Double(n)

        // Per-difficulty breakdown — an 85% average can hide 50% on the hard cases.
        var byDifficulty: [String: DifficultyStat] = [:]
        for (tag, group) in Dictionary(grouping: rows, by: \.difficulty) {
            let matches = group.filter { octaveCorrectedError($0) <= bar.matchToleranceBPM }.count
            let mae = mean(group.map(octaveCorrectedError))
            byDifficulty[tag] = DifficultyStat(
                count: group.count,
                octaveMatchRate: group.isEmpty ? 0 : Double(matches) / Double(group.count),
                meanAbsErrorOctaveCorrected: mae)
        }

        // Confidence calibration.
        let high = rows.filter { $0.confidence >= bar.highConfidenceThreshold }
        let low = rows.filter { $0.confidence < bar.highConfidenceThreshold }
        let highErrRate = errorRate(high, tolerance: bar.matchToleranceBPM)
        let lowErrRate = errorRate(low, tolerance: bar.matchToleranceBPM)
        let predicts = !high.isEmpty && !low.isEmpty && lowErrRate > highErrRate

        // Octave-flag recall on the octave-only-error cases.
        let octaveOnly = rows.filter {
            octaveCorrectedError($0) <= bar.matchToleranceBPM && rawError($0) > bar.matchToleranceBPM
        }
        let flagged = octaveOnly.filter { $0.octaveFlag != .none }.count
        let octaveFlagRecall = octaveOnly.isEmpty ? 1.0 : Double(flagged) / Double(octaveOnly.count)

        let medianOct = median(octErrors)
        let verdict = verdict(octaveMatchRate: octMatchRate, medianOctaveError: medianOct,
                              highConfidenceErrorRate: highErrRate,
                              confidencePredictsError: predicts, bar: bar)

        return BPMAccuracyReport(
            count: n,
            exactMatchRate: n == 0 ? 0 : Double(exact) / Double(n),
            octaveCorrectedMatchRate: octMatchRate,
            meanAbsErrorRaw: mean(rawErrors), medianAbsErrorRaw: median(rawErrors),
            meanAbsErrorOctaveCorrected: mean(octErrors),
            medianAbsErrorOctaveCorrected: medianOct,
            byDifficulty: byDifficulty,
            highConfidenceErrorRate: highErrRate, lowConfidenceErrorRate: lowErrRate,
            confidencePredictsError: predicts, octaveFlagRecall: octaveFlagRecall,
            verdict: verdict)
    }

    // MARK: - Metric helpers

    static func rawError(_ r: GroundTruthResult) -> Double { abs(r.detectedBPM - r.trueBPM) }

    /// Smallest error after allowing a half/double-time reinterpretation.
    static func octaveCorrectedError(_ r: GroundTruthResult) -> Double {
        [r.detectedBPM, r.detectedBPM * 2, r.detectedBPM / 2]
            .map { abs($0 - r.trueBPM) }.min() ?? .infinity
    }

    private static func errorRate(_ rows: [GroundTruthResult], tolerance: Double) -> Double {
        guard !rows.isEmpty else { return 0 }
        let wrong = rows.filter { octaveCorrectedError($0) > tolerance }.count
        return Double(wrong) / Double(rows.count)
    }

    private static func verdict(octaveMatchRate: Double, medianOctaveError: Double,
                                highConfidenceErrorRate: Double, confidencePredictsError: Bool,
                                bar: AccuracyBar) -> AccuracyVerdict {
        if octaveMatchRate < bar.redOctaveMatch
            || highConfidenceErrorRate > bar.redHighConfidenceErrorRate {
            return .red
        }
        if octaveMatchRate >= bar.greenOctaveMatch
            && medianOctaveError <= bar.greenMedianError
            && confidencePredictsError {
            return .green
        }
        return .yellow
    }

    private static func mean(_ xs: [Double]) -> Double {
        xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
    }

    private static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }
}
