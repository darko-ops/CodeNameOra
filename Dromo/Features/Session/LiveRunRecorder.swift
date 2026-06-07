import Foundation
import DromoCore

extension Notification.Name {
    /// Posted after a live run is persisted, so the You-tab dashboard can refresh.
    static let dromoSessionSaved = Notification.Name("dromoSessionSaved")
}

/// Accumulates a LiveLoop run into a DromoCore `Session` — pace log, integrated
/// distance, and per-track plays — so the new live flow persists through the SAME
/// `SessionRepository` path as the old flow and shows up on the You-tab dashboard
/// (Momentum / Total / Listens / Most-Played), Goals (weekly sessions + distance),
/// and the Sessions list.
///
/// Pure bookkeeping: fed one sample per ~second from the live loop, it tracks the
/// currently-playing track and closes out each play on change.
struct LiveRunRecorder {

    private let targetPaceSecPerKm: Double
    private let startedAt: Date
    private let trackByID: [String: Track]

    private var paces: [PaceLog] = []
    private var plays: [TrackPlay] = []
    private var distanceMeters: Double = 0
    private var lastSampleAt: Date?
    private var currentTrackID: String?
    private var currentPlayStart: Date?

    init(targetPaceSecPerKm: Double, startedAt: Date, tracks: [Track]) {
        self.targetPaceSecPerKm = targetPaceSecPerKm
        self.startedAt = startedAt
        self.trackByID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Feed one live sample (~1 Hz). `paceSecPerKm <= 0` means GPS isn't ready — it
    /// contributes no distance and no pace-log row (indoor runs still log track plays).
    mutating func sample(paceSecPerKm: Double, bpm: Double, trackID: String?, at now: Date) {
        // Distance: integrate speed (m/s = 1000 / pace) over the inter-sample interval.
        if let last = lastSampleAt, paceSecPerKm > 0 {
            let dt = now.timeIntervalSince(last)
            if dt > 0, dt < 10 {   // skip long gaps (e.g. backgrounding)
                distanceMeters += (1_000.0 / paceSecPerKm) * dt
            }
        }
        lastSampleAt = now

        if paceSecPerKm > 0 {
            paces.append(PaceLog(
                timestamp: now,
                paceSecondsPerKm: paceSecPerKm,
                targetPaceSecondsPerKm: targetPaceSecPerKm,
                bpmPlaying: bpm,
                gapSeconds: paceSecPerKm - targetPaceSecPerKm,
                accuracyMeters: 0, latitude: 0, longitude: 0))
        }

        if trackID != currentTrackID {
            closeCurrentPlay(at: now)
            currentTrackID = trackID
            currentPlayStart = (trackID == nil) ? nil : now
        }
    }

    /// Close the run and produce the persistable `Session`.
    mutating func finish(at now: Date) -> Session {
        closeCurrentPlay(at: now)
        return Session(
            startedAt: startedAt,
            endedAt: now,
            targetPace: targetPaceSecPerKm,
            actualPaces: paces,
            tracks: plays,
            distanceMeters: distanceMeters,
            elapsedSeconds: max(0, Int(now.timeIntervalSince(startedAt))),
            status: .completed)
    }

    private mutating func closeCurrentPlay(at now: Date) {
        guard let id = currentTrackID, let start = currentPlayStart,
              let track = trackByID[id] else { return }
        let reason: TrackPlay.SelectionReason = plays.isEmpty ? .initial : .trackEnded
        plays.append(TrackPlay(track: track, startedAt: start, endedAt: now,
                               reasonForSelection: reason))
    }
}
