import Foundation

/// Maps a pace gap to a BPM target. This is the decision logic that turns
/// "how far off pace am I?" into "what tempo should the music be?" (Section 5.2).
public struct BPMAdapter {

    /// Maximum BPM change permitted per update — keeps the music from lurching.
    public static let maxOffsetPerUpdate: Double = 2.0

    /// Gap values beyond this magnitude are clamped before mapping.
    public static let maxConsideredGap: Double = 60.0

    /// Returns a BPM offset to apply to the base BPM.
    ///
    /// - Parameter gapSecondsPerKm: positive = too slow, negative = too fast.
    public static func bpmOffset(
        forGap gapSecondsPerKm: Double,
        sensitivity: UserSettings.BPMSensitivity,
        settings: UserSettings
    ) -> Double {
        let multiplier: Double
        switch sensitivity {
        case .conservative: multiplier = 0.2
        case .standard:     multiplier = 0.4
        case .aggressive:   multiplier = 0.8
        }

        // Clamp gap to ±60 seconds to prevent extreme BPM jumps.
        let clampedGap = max(-maxConsideredGap, min(maxConsideredGap, gapSecondsPerKm))

        // Linear mapping: a 10s gap → multiplier × 10 BPM offset.
        let rawOffset = clampedGap * multiplier

        // Smoothing — BPM changes should never exceed `maxOffsetPerUpdate`.
        return max(-maxOffsetPerUpdate, min(maxOffsetPerUpdate, rawOffset))
    }

    /// Returns the absolute target BPM, clamped to the user's floor/ceiling.
    public static func targetBPM(
        baseBPM: Double,
        gap: Double,
        sensitivity: UserSettings.BPMSensitivity,
        settings: UserSettings
    ) -> Double {
        let offset = bpmOffset(forGap: gap, sensitivity: sensitivity, settings: settings)
        let rawTarget = baseBPM + offset

        // Clamp to the user-defined BPM floor and ceiling.
        return max(settings.minBPM, min(settings.maxBPM, rawTarget))
    }
}
