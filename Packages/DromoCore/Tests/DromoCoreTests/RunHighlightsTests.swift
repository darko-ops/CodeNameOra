import XCTest
@testable import DromoCore

/// Phase 6: the surfaces that make learning visible must be TRUE — the summary can
/// only say what was measured, the "why this track?" answer has to be the actual
/// reason, and reset has to erase.
final class RunHighlightsTests: XCTestCase {

    private func response(_ id: String, _ mode: PaceMode, reward: Double,
                          samples: Int = 90) -> TrackResponse {
        TrackResponse(trackID: id, mode: mode, reward: reward, samples: samples)
    }

    // MARK: - What moved you

    func testHighlightsRankByMeasuredEffect() {
        let highlights = RunHighlights.from([
            response("meh", .push, reward: 1),
            response("best", .push, reward: 9),
            response("mid", .push, reward: 4),
        ])
        XCTAssertEqual(highlights.map(\.trackID), ["best", "mid", "meh"])
    }

    func testShortPlaysAreNotPresentedAsFindings() {
        // 20 samples ≈ 20 seconds: noise, not evidence. Showing it would teach the
        // runner to distrust the whole section.
        let highlights = RunHighlights.from([response("blip", .push, reward: 12, samples: 20)])
        XCTAssertTrue(highlights.isEmpty)
        XCTAssertTrue(RunHighlights.isEmpty([response("blip", .push, reward: 12, samples: 20)]))
    }

    func testHeadlineStatesWhatWasObservedNotWhatCausedIt() {
        let pushed = RunHighlight(trackID: "a", mode: .push, reward: 6, samples: 90)
        XCTAssertEqual(pushed.headline, "Your cadence came up 6 spm while this played")
        XCTAssertEqual(pushed.context, "when you were behind pace")
        // No causal claim anywhere in the copy.
        for word in ["made you", "caused", "because of this"] {
            XCTAssertFalse(pushed.headline.lowercased().contains(word))
        }
    }

    func testHeadlineReadsCorrectlyForEachMode() {
        XCTAssertEqual(RunHighlight(trackID: "a", mode: .settle, reward: 5, samples: 90).headline,
                       "You eased down 5 spm — back toward target")
        XCTAssertEqual(RunHighlight(trackID: "a", mode: .push, reward: -4, samples: 90).headline,
                       "You drifted 4 spm further behind")
        XCTAssertEqual(RunHighlight(trackID: "a", mode: .hold, reward: 0.5, samples: 90).headline,
                       "You closed 0.5 spm and held the groove",
                       "sub-1 spm keeps a decimal rather than rounding to a meaningless 0")
    }

    func testDragIsOnlyReportedWhenItIsRealNotMerelyUnremarkable() {
        XCTAssertNil(RunHighlights.drag([response("flat", .push, reward: -0.5)]),
                     "a track that did nothing much is not worth nagging about")
        XCTAssertEqual(RunHighlights.drag([response("heavy", .push, reward: -6)])?.trackID, "heavy")
    }

    func testHighlightsAreCappedSoTheSummaryStaysReadable() {
        let many = (1...10).map { response("t\($0)", .push, reward: Double($0)) }
        XCTAssertEqual(RunHighlights.from(many).count, 3)
    }

    // MARK: - Why this track?

    private func facts(_ id: String, bpm: Double) -> TrackFacts {
        TrackFacts(id: id, bpm: bpm, bpmConfidence: 0.9, tempoOctaveFlag: .none,
                   energy: 0.5, beatStrength: 0.7, analysisVersion: "test")
    }

    func testReasonReportsLearnedPushOnlyOnceEvidenceIsEarned() {
        var engine = SelectionEngine()
        let config = SelectionConfig()
        let decision = engine.selectNext(
            targetCadence: 170, currentCadence: 170, candidates: [facts("a", bpm: 170)],
            effectiveness: ["a": LearnedEffectiveness(value: 0.9,
                                                      observations: config.minObservationsToTrust)])
        XCTAssertEqual(decision?.reason, .learnedPush(observations: config.minObservationsToTrust))
        XCTAssertEqual(decision?.reason.label, "This one moves you")
    }

    func testReasonSaysExploringForATrackNeverPlayed() {
        var engine = SelectionEngine()
        let decision = engine.selectNext(targetCadence: 170, currentCadence: 170,
                                         candidates: [facts("fresh", bpm: 170)])
        XCTAssertEqual(decision?.reason, .exploring)
    }

    func testReasonDoesNotClaimLearningOnThinEvidence() {
        // One play is not "this one moves you" — the answer must match what the engine
        // actually acted on, which at one observation is mostly tempo.
        var engine = SelectionEngine()
        let decision = engine.selectNext(
            targetCadence: 170, currentCadence: 170, candidates: [facts("a", bpm: 170)],
            effectiveness: ["a": LearnedEffectiveness(value: 0.95, observations: 1)])
        XCTAssertNotEqual(decision?.reason, .learnedPush(observations: 1))
    }

    func testReasonCreditsTasteWhenThatIsWhatSeparatedIt() {
        var engine = SelectionEngine()
        let decision = engine.selectNext(
            targetCadence: 170, currentCadence: 170, candidates: [facts("liked", bpm: 170)],
            preferences: ["liked": 1.0],
            effectiveness: ["liked": LearnedEffectiveness(value: 0.5, observations: 4)])
        XCTAssertEqual(decision?.reason, .taste)
    }

    func testLearnedPushDetailPluralisesHonestly() {
        XCTAssertTrue(SelectionEngine.Reason.learnedPush(observations: 1).detail.contains("1 play,"))
        XCTAssertTrue(SelectionEngine.Reason.learnedPush(observations: 4).detail.contains("4 plays,"))
    }

    // MARK: - Reset actually clears

    func testResetErasesLearnedEffectiveness() async {
        let store = InMemoryEffectivenessStore()
        await store.record(TrackResponse(trackID: "a", mode: .push, reward: 8, samples: 60))
        let before = await store.learned(for: .push)
        XCTAssertFalse(before.isEmpty)

        await store.reset()

        for mode in PaceMode.allCases {
            let learned = await store.learned(for: mode)
            let values = await store.effectiveness(for: mode)
            XCTAssertTrue(learned.isEmpty, "\(mode) survived reset")
            XCTAssertTrue(values.isEmpty)
        }
    }

    func testResetErasesStatedTaste() async {
        let store = InMemoryPreferenceStore()
        await store.record(.liked, trackID: "a")
        await store.record(.skipped, trackID: "b")
        let before = await store.weights()
        XCTAssertFalse(before.isEmpty)

        await store.reset()
        let after = await store.weights()
        XCTAssertTrue(after.isEmpty)
    }

    func testLearningResumesCleanlyAfterReset() async {
        // Reset must clear the evidence, not poison the store: the next play starts
        // from one observation, not from a remembered count.
        let store = InMemoryEffectivenessStore()
        await store.record(TrackResponse(trackID: "a", mode: .push, reward: 8, samples: 60))
        await store.reset()
        await store.record(TrackResponse(trackID: "a", mode: .push, reward: 8, samples: 60))

        let learned = await store.learned(for: .push)
        XCTAssertEqual(learned["a"]?.observations, 1)
    }
}
