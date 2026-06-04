import Foundation
import CoreLocation
import Combine
import DromoCore

/// Drives one running session end to end (Section 5).
///
/// It owns the DromoCore engine pieces and processes pace readings from a
/// `PaceSource`:
///   reading → PaceEngine (smoothing) → gap → BPMAdapter (ramped target BPM)
///   → MusicSequencer (closest-BPM track) → UI.
///
/// On device the source is `LocationManager` (real GPS); in the Simulator it's
/// `SimulatedPaceSource`, fed by the on-screen pace control. `usesSimulatedPace`
/// tells the UI whether to show that control.
@MainActor
final class SessionController: ObservableObject {

    enum Phase: Equatable {
        case countdown(Int)
        case running
        case paused
        case finished
    }

    // MARK: - Published UI state
    @Published private(set) var phase: Phase = .countdown(3)
    @Published private(set) var currentPaceSecondsPerKm: Double = 0
    @Published private(set) var gap: Double = 0
    @Published private(set) var targetBPM: Double = 0
    @Published private(set) var currentTrack: Track?
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var trackChanges: Int = 0
    @Published private(set) var bpmHistory: [Double] = []
    /// Per-tick log (pace, BPM, gap, coordinate) — feeds the chart and export.
    @Published private(set) var samples: [PaceLog] = []

    /// Built when the run ends — the immutable record handed to export.
    private(set) var completedSession: Session?

    /// The user's (simulated) actual pace. Starts on target; the control nudges it.
    @Published var simulatedPaceSecondsPerKm: Double

    // MARK: - Configuration
    let targetPaceSecondsPerKm: Double
    let settings: UserSettings

    /// True when pace is simulated (Simulator) → the UI shows the pace control.
    let usesSimulatedPace: Bool

    var status: RunFeedback.Status { RunFeedback.status(forGap: gap) }

    /// Demo affordance: the sequencer's min-play clock runs faster than wall time
    /// so track changes are visible in a short simulator run. Real runs use 1.0.
    private let demoTimeScale: Double = 6.0

    // MARK: - Engine
    private let engine = PaceEngine()
    private let library: InMemoryBPMLibrary
    private let sequencer: MusicSequencer
    private var loop: Task<Void, Never>?
    private var paceSource: PaceSource?

    /// Invoked when the sequencer switches tracks — drives real Spotify playback
    /// (no-op for the mock provider).
    private let playback: ((Track) async -> Void)?

    // Running totals for the summary.
    private var gapSum: Double = 0
    private var gapSamples: Int = 0

    // Run record state. Coordinates are dead-reckoned from speed so the demo
    // produces a real GPS path; on device these come from CoreLocation.
    private var startedAt = Date()
    private var trackPlays: [TrackPlay] = []
    private var latitude = 37.7749       // start point (San Francisco)
    private let longitude = -122.4194

    init(targetPaceSecondsPerKm: Double,
         settings: UserSettings,
         tracks: [Track],
         playback: ((Track) async -> Void)? = nil) {
        self.targetPaceSecondsPerKm = targetPaceSecondsPerKm
        self.settings = settings
        self.simulatedPaceSecondsPerKm = targetPaceSecondsPerKm
        self.library = InMemoryBPMLibrary(tracks: tracks)
        self.playback = playback
        #if targetEnvironment(simulator)
        self.usesSimulatedPace = true
        #else
        self.usesSimulatedPace = false
        #endif

        let start = Date()
        let scale = demoTimeScale
        self.sequencer = MusicSequencer(
            library: library,
            crossfader: CrossfadeController(),
            now: { start.addingTimeInterval(Date().timeIntervalSince(start) * scale) }
        )
        // Seed the ramped BPM target in the middle of the user's range.
        self.targetBPM = min(max(155, settings.minBPM), settings.maxBPM)
    }

    // MARK: - Lifecycle

    func begin() {
        guard loop == nil else { return }
        loop = Task { await run() }
    }

    func togglePause() {
        switch phase {
        case .running: phase = .paused
        case .paused:  phase = .running
        default: break
        }
    }

    func end() {
        paceSource?.stop()
        loop?.cancel()
        loop = nil
        phase = .finished
        if !trackPlays.isEmpty { trackPlays[trackPlays.count - 1].endedAt = Date() }
        completedSession = Session(
            startedAt: startedAt,
            endedAt: Date(),
            targetPace: targetPaceSecondsPerKm,
            actualPaces: samples,
            tracks: trackPlays,
            distanceMeters: distanceMeters,
            elapsedSeconds: Int(elapsedSeconds),
            status: .completed
        )
    }

    /// Pace-source callback (any thread) → hop to the main actor to process.
    nonisolated private func receive(_ reading: PaceReading) {
        Task { @MainActor [weak self] in await self?.process(reading) }
    }

    private func makePaceSource() -> PaceSource {
        #if targetEnvironment(simulator)
        return SimulatedPaceSource(paceProvider: { [weak self] in
            self?.simulatedPaceSecondsPerKm ?? self?.targetPaceSecondsPerKm ?? 360
        })
        #else
        return LocationManager()
        #endif
    }

    // MARK: - Summary

    var averageGap: Double { gapSamples > 0 ? gapSum / Double(gapSamples) : 0 }
    var averagePaceSecondsPerKm: Double {
        elapsedSeconds > 0 && distanceMeters > 0 ? elapsedSeconds / (distanceMeters / 1_000) : 0
    }

    // MARK: - Loop

    private func run() async {
        await engine.setTargetPace(targetPaceSecondsPerKm)
        await engine.setActive(true)

        // 3-2-1 countdown.
        for n in stride(from: 3, through: 1, by: -1) {
            phase = .countdown(n)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
        }
        phase = .running
        startedAt = Date()

        // Start the pace source; it drives `process(_:)` via `receive(_:)`.
        let source = makePaceSource()
        paceSource = source
        source.onReading = { [weak self] reading in self?.receive(reading) }
        source.start()

        // Keep the task alive so cancellation can stop the source cleanly.
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        source.stop()
    }

    /// One pace reading → smoothed pace → gap → ramped BPM → track selection.
    private func process(_ reading: PaceReading) async {
        guard phase == .running else { return }

        let speed = reading.speedMetersPerSecond
        // Use the real coordinate when present; otherwise dead-reckon northward.
        let lat: Double, lon: Double
        if let coordinate = reading.coordinate {
            lat = coordinate.latitude; lon = coordinate.longitude
        } else {
            latitude += speed / 111_320.0
            lat = latitude; lon = longitude
        }

        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0,
            horizontalAccuracy: reading.accuracyMeters,
            verticalAccuracy: reading.accuracyMeters,
            course: 0,
            speed: speed,
            timestamp: Date()
        )
        _ = await engine.ingestLocation(location)

        let pace = await engine.currentPaceSecondsPerKm
        let gap = await engine.currentGap()

        // Ramp the running BPM target toward what the gap demands (±2 BPM/update,
        // clamped to the user's floor/ceiling).
        let nextBPM = BPMAdapter.targetBPM(
            baseBPM: targetBPM,
            gap: gap,
            sensitivity: settings.bpmSensitivity,
            settings: settings
        )

        await sequencer.selectTrack(forTargetBPM: nextBPM)
        let selected = sequencer.currentTrack
        let previousID = currentTrack?.id
        if let selected, selected.id != previousID {
            if previousID != nil { trackChanges += 1 }
            if !trackPlays.isEmpty { trackPlays[trackPlays.count - 1].endedAt = Date() }
            trackPlays.append(TrackPlay(
                track: selected,
                startedAt: Date(),
                reasonForSelection: previousID == nil ? .initial : (gap > 0 ? .paceIncrease : .paceDecrease)
            ))
            if let playback { Task { await playback(selected) } }   // real playback on device
        }

        samples.append(PaceLog(
            timestamp: Date(),
            paceSecondsPerKm: pace,
            targetPaceSecondsPerKm: targetPaceSecondsPerKm,
            bpmPlaying: selected?.bpm ?? nextBPM,
            gapSeconds: gap,
            accuracyMeters: reading.accuracyMeters,
            latitude: lat,
            longitude: lon
        ))

        currentPaceSecondsPerKm = pace
        self.gap = gap
        targetBPM = nextBPM
        currentTrack = selected
        gapSum += abs(gap); gapSamples += 1
        bpmHistory.append(nextBPM)   // ramped target BPM, aligned 1:1 with `samples`
        elapsedSeconds += 1
        distanceMeters += speed       // dt ≈ 1s per reading
    }
}
