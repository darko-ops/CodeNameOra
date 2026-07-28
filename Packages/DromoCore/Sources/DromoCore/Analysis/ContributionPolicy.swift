import Foundation

/// Governs whether an analysis result may be published to the Global Track Table.
///
/// This is a VALVE, deliberately closed. Publishing a fact keyed by ISRC pushes it to
/// every other runner who owns that recording, so a systematically wrong analyzer
/// wouldn't mis-pace one person — it would mis-pace everyone, and the bad value would
/// outlive the bug. The project's rule is that the accuracy bar is measured before
/// anything is built on top of it, so the default is `pending`: the pipeline runs, and
/// publishes nothing.
///
/// To open it, run the harness on a real ground-truth set, record the verdict in
/// `findings/bpm-accuracy.md`, then change `current` to match. Both are required — a
/// verdict in code with a blank findings table is exactly the fabrication the bar
/// exists to prevent.
public struct ContributionPolicy: Sendable, Equatable {

    public let verdict: AccuracyVerdict
    /// GREEN: the floor below which a reading is a guess, not a contribution.
    public var greenFloor: Double
    /// YELLOW: only readings this confident may be shared, since the mitigation for a
    /// mixed result is precisely to trust the confident ones and no others.
    public var yellowFloor: Double

    public init(verdict: AccuracyVerdict, greenFloor: Double = 0.5, yellowFloor: Double = 0.8) {
        self.verdict = verdict
        self.greenFloor = greenFloor
        self.yellowFloor = yellowFloor
    }

    /// THE VALVE. `pending` until a real measurement says otherwise.
    ///
    /// Changing this line is the whole act of opening the contributor path — one
    /// constant, one place, so it can't be opened by accident or in pieces.
    public static let current = ContributionPolicy(verdict: .pending)

    /// May the app analyze and publish at all? False under `pending` and `red`, so a
    /// RED verdict retires the feature by flipping the same constant.
    public var allowsContribution: Bool {
        verdict == .green || verdict == .yellow
    }

    /// May THIS result be published? Confidence is the gate, per the verdict.
    public func mayPublish(_ result: AnalysisResult) -> Bool {
        guard allowsContribution, result.bpm > 0 else { return false }
        switch verdict {
        case .green:  return result.bpmConfidence >= greenFloor
        case .yellow: return result.bpmConfidence >= yellowFloor
        case .pending, .red: return false
        }
    }

    /// Why contribution is off, in words a Settings screen can show. Nil when open.
    public var closedReason: String? {
        switch verdict {
        case .pending:
            return "Dromo's tempo analysis hasn't been checked against known-BPM music "
                 + "yet. Until it has, your phone won't share tempo readings — a wrong "
                 + "one would reach everyone who owns the same song."
        case .red:
            return "Dromo's tempo analysis didn't meet the accuracy bar, so it doesn't "
                 + "share readings. Tempo comes from lookups and built-in mixes instead."
        case .yellow, .green:
            return nil
        }
    }
}
