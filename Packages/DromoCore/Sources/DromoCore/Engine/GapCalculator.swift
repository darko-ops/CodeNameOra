import Foundation

/// Computes the pace gap: the delta between actual and target pace.
///
/// Sign convention (Section 5.1):
/// - Positive  → running slower than target (need to speed up)
/// - Negative  → running faster than target (need to slow down)
/// - Zero      → exactly on pace
public enum GapCalculator {
    public static func gap(
        actualPaceSecondsPerKm actual: Double,
        targetPaceSecondsPerKm target: Double
    ) -> Double {
        actual - target
    }
}
