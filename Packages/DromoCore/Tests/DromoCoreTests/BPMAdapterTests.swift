import XCTest
@testable import DromoCore

final class BPMAdapterTests: XCTestCase {

    private let settings = UserSettings.default  // minBPM 110, maxBPM 180

    func test_bpmOffset_conservativeSensitivity_smallOffset() {
        // gap 2 → 2 × 0.2 = 0.4 (unclamped)
        let offset = BPMAdapter.bpmOffset(forGap: 2, sensitivity: .conservative, settings: settings)
        XCTAssertEqual(offset, 0.4, accuracy: 0.0001)
    }

    func test_bpmOffset_aggressiveSensitivity_largerOffset() {
        // Same small gap: aggressive (×0.8) must exceed conservative (×0.2).
        let conservative = BPMAdapter.bpmOffset(forGap: 2, sensitivity: .conservative, settings: settings)
        let aggressive = BPMAdapter.bpmOffset(forGap: 2, sensitivity: .aggressive, settings: settings)
        XCTAssertEqual(aggressive, 1.6, accuracy: 0.0001)
        XCTAssertGreaterThan(aggressive, conservative)
    }

    func test_bpmOffset_largeGap_isClamped() {
        // gap 100 → clamped gap 60 → 60 × 0.4 = 24 → clamped to maxOffsetPerUpdate (2.0)
        let offset = BPMAdapter.bpmOffset(forGap: 100, sensitivity: .standard, settings: settings)
        XCTAssertEqual(offset, BPMAdapter.maxOffsetPerUpdate, accuracy: 0.0001)

        // Symmetric on the negative side.
        let negative = BPMAdapter.bpmOffset(forGap: -100, sensitivity: .standard, settings: settings)
        XCTAssertEqual(negative, -BPMAdapter.maxOffsetPerUpdate, accuracy: 0.0001)
    }

    func test_targetBPM_neverExceedsMaxBPM() {
        // Base at the ceiling, a positive gap would push above it.
        let target = BPMAdapter.targetBPM(
            baseBPM: settings.maxBPM,
            gap: 50,
            sensitivity: .aggressive,
            settings: settings
        )
        XCTAssertLessThanOrEqual(target, settings.maxBPM)
        XCTAssertEqual(target, settings.maxBPM, accuracy: 0.0001)
    }

    func test_targetBPM_neverBelowMinBPM() {
        // Base at the floor, a negative gap would push below it.
        let target = BPMAdapter.targetBPM(
            baseBPM: settings.minBPM,
            gap: -50,
            sensitivity: .aggressive,
            settings: settings
        )
        XCTAssertGreaterThanOrEqual(target, settings.minBPM)
        XCTAssertEqual(target, settings.minBPM, accuracy: 0.0001)
    }

    func test_targetBPM_appliesOffsetWithinRange() {
        // Base 150, gap 2, standard (×0.4) → +0.8 → 150.8, within [110, 180].
        let target = BPMAdapter.targetBPM(
            baseBPM: 150,
            gap: 2,
            sensitivity: .standard,
            settings: settings
        )
        XCTAssertEqual(target, 150.8, accuracy: 0.0001)
    }
}
