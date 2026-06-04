import Foundation

/// Selects the next track given a BPM target (Section 5.3).
///
/// Runs on a cadence (every ~10s) and on track completion. The `Date()` calls
/// from the spec are routed through an injectable `now` clock so the minimum
/// play-duration rule is deterministically testable; behaviour is otherwise
/// identical to the specification.
@MainActor
public final class MusicSequencer: ObservableObject {

    // MARK: - State
    @Published public private(set) var currentTrack: Track?
    @Published public private(set) var queue: [Track] = []

    private let bpmTolerance: Double = 8.0     // accept tracks within ±8 BPM
    private let fallbackTolerance: Double = 15.0
    private let minPlayDuration: Double = 60.0
    /// New track must beat the current one by at least this many BPM to switch.
    private let switchImprovementThreshold: Double = 3.0
    private var currentTrackStartTime: Date?

    // MARK: - Dependencies
    private let library: BPMLibraryProviding
    private let crossfader: TrackTransitioning
    private let now: () -> Date

    public init(
        library: BPMLibraryProviding,
        crossfader: TrackTransitioning,
        now: @escaping () -> Date = Date.init
    ) {
        self.library = library
        self.crossfader = crossfader
        self.now = now
    }

    // MARK: - Core selection
    public func selectTrack(forTargetBPM targetBPM: Double) async {
        let candidates = await library.tracks(nearBPM: targetBPM, tolerance: bpmTolerance)

        guard !candidates.isEmpty else {
            // Fallback: expand tolerance.
            let fallback = await library.tracks(nearBPM: targetBPM, tolerance: fallbackTolerance)
            guard let track = fallback.randomElement() else { return }
            await transition(to: track)
            return
        }

        // Sort by BPM proximity, excluding the currently playing track.
        let sorted = candidates
            .filter { $0.id != currentTrack?.id }
            .sorted { abs($0.bpm - targetBPM) < abs($1.bpm - targetBPM) }

        guard let best = sorted.first else { return }

        // Only transition if the BPM delta justifies it.
        if let current = currentTrack {
            let currentDelta = abs(current.bpm - targetBPM)
            let bestDelta = abs(best.bpm - targetBPM)

            // Don't switch unless the new track is meaningfully better.
            guard bestDelta < currentDelta - switchImprovementThreshold else { return }

            // Enforce minimum play time.
            if let start = currentTrackStartTime,
               now().timeIntervalSince(start) < minPlayDuration { return }
        }

        await transition(to: best)
    }

    private func transition(to track: Track) async {
        currentTrack = track
        currentTrackStartTime = now()
        await crossfader.crossfade(to: track)
    }
}
