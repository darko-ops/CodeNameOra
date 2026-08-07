import XCTest
import DromoCore
@testable import Dromo

/// Cover for the figures a finished run is described by.
///
/// These used to live on `SessionController`, which is why the post-run summary could
/// only be shown after a flow nothing reached. They now derive from the recorded
/// `Session` — the thing a live run actually produces — so the summary works after any
/// run, and the arithmetic is worth pinning because a plausible-looking average is the
/// easy way to publish a wrong number.
final class RunSummaryTests: XCTestCase {

    private func log(pace: Double, target: Double = 300, bpm: Double = 160,
                     at offset: TimeInterval = 0) -> PaceLog {
        PaceLog(timestamp: Date(timeIntervalSince1970: offset),
                paceSecondsPerKm: pace,
                targetPaceSecondsPerKm: target,
                bpmPlaying: bpm,
                gapSeconds: pace - target,
                accuracyMeters: 5, latitude: 0, longitude: 0)
    }

    private func session(distance: Double, seconds: Int,
                         paces: [PaceLog] = [], tracks: [TrackPlay] = []) -> Session {
        Session(startedAt: Date(timeIntervalSince1970: 0),
                endedAt: Date(timeIntervalSince1970: TimeInterval(seconds)),
                targetPace: 300,
                actualPaces: paces,
                tracks: tracks,
                distanceMeters: distance,
                elapsedSeconds: seconds,
                status: .completed)
    }

    /// Average pace comes from distance over time, not from averaging the samples.
    /// 5 km in 25 minutes is 5:00/km however uneven the run was.
    func test_averagePaceIsDistanceOverTime() {
        let summary = RunSummary(session: session(distance: 5_000, seconds: 1_500))

        XCTAssertEqual(summary.averagePaceSecondsPerKm, 300, accuracy: 0.01)
    }

    /// The reason it isn't a mean of samples: standing still reports an enormous pace
    /// for every second it lasts, so the mean is dragged far off what was actually run.
    func test_aPauseDoesNotDistortAveragePace() {
        // 5 km in 25 minutes, but with a long stationary stretch logged.
        let paces = Array(repeating: log(pace: 300), count: 20)
            + Array(repeating: log(pace: 6_000), count: 10)   // barely moving
        let summary = RunSummary(session: session(distance: 5_000, seconds: 1_500, paces: paces))

        XCTAssertEqual(summary.averagePaceSecondsPerKm, 300, accuracy: 0.01)
        XCTAssertLessThan(summary.averagePaceSecondsPerKm, 1_000,
                          "A sample mean would report roughly 2200 s/km here")
    }

    /// An indoor run has no GPS distance, but it still has a pace worth reporting.
    func test_fallsBackToSampleMeanWithoutDistance() {
        let paces = [log(pace: 280), log(pace: 320)]
        let summary = RunSummary(session: session(distance: 0, seconds: 600, paces: paces))

        XCTAssertEqual(summary.averagePaceSecondsPerKm, 300, accuracy: 0.01)
    }

    /// Off-pace is the absolute gap: two minutes fast and two minutes slow is not the
    /// same as having run on pace, and a signed mean would say it was.
    func test_offPaceUsesTheAbsoluteGap() {
        let paces = [log(pace: 240), log(pace: 360)]   // 60 under, 60 over

        let summary = RunSummary(session: session(distance: 2_000, seconds: 600, paces: paces))

        XCTAssertEqual(summary.averageGap, 60, accuracy: 0.01)
    }

    /// Tempo range comes from what actually played.
    func test_bpmRangeReadsWhatPlayed() {
        let paces = [log(pace: 300, bpm: 150), log(pace: 300, bpm: 175)]

        let summary = RunSummary(session: session(distance: 2_000, seconds: 600, paces: paces))

        XCTAssertEqual(summary.bpmRangeText, "150–175")
    }

    /// A run where nothing carried a tempo says so, rather than printing a range of 0.
    func test_noTempoMeansNoRange() {
        let paces = [log(pace: 300, bpm: 0)]

        let summary = RunSummary(session: session(distance: 1_000, seconds: 300, paces: paces))

        XCTAssertNil(summary.bpmRangeText)
    }

    /// An empty run doesn't divide by zero on the way to a summary.
    func test_anEmptyRunIsSafeToSummarise() {
        let summary = RunSummary(session: session(distance: 0, seconds: 0))

        XCTAssertEqual(summary.averagePaceSecondsPerKm, 0)
        XCTAssertEqual(summary.averageGap, 0)
        XCTAssertEqual(summary.trackChanges, 0)
        XCTAssertNil(summary.bpmRangeText)
    }
}
