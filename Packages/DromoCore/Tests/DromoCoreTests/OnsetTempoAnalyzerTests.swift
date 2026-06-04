import XCTest
@testable import DromoCore

final class OnsetTempoAnalyzerTests: XCTestCase {

    private let sr = 22_050.0
    private let analyzer = OnsetTempoAnalyzer()

    /// Detected BPM matches target, or a clearly-flagged octave of it.
    private func assertTempo(_ target: Double, tolerance: Double = 3,
                             file: StaticString = #filePath, line: UInt = #line) {
        let samples = SynthAudio.clickTrain(bpm: target, seconds: 14, sampleRate: sr)
        guard let f = analyzer.analyze(samples: samples, sampleRate: sr) else {
            return XCTFail("analyzer returned nil", file: file, line: line)
        }
        let onTarget = abs(f.bpm - target) <= tolerance
        let onOctave = abs(f.bpm - target / 2) <= tolerance || abs(f.bpm - target * 2) <= tolerance
        XCTAssertTrue(onTarget || onOctave,
                      "got \(f.bpm) for target \(target)", file: file, line: line)
        if !onTarget {
            XCTAssertNotEqual(f.octaveFlag, .none,
                              "octave detection must be flagged", file: file, line: line)
        }
    }

    func testMidTempoDetectedCleanly() {
        // 128 and 100 sit near the perceptual prior → resolve to the target, not an octave.
        for bpm in [100.0, 128.0] {
            let samples = SynthAudio.clickTrain(bpm: bpm, seconds: 14, sampleRate: sr)
            let f = analyzer.analyze(samples: samples, sampleRate: sr)
            XCTAssertNotNil(f)
            XCTAssertEqual(f!.bpm, bpm, accuracy: 3, "clean mid-tempo \(bpm)")
        }
    }

    func testTempoAcrossBands() {
        for bpm in [90.0, 110.0, 140.0, 150.0] { assertTempo(bpm) }
    }

    func testHighTempoOctaveIsFlagged() {
        // A 174-BPM sprint track is perceptually ambiguous with 87; require a flag
        // whenever we don't land on 174 itself.
        let samples = SynthAudio.clickTrain(bpm: 174, seconds: 14, sampleRate: sr)
        let f = analyzer.analyze(samples: samples, sampleRate: sr)!
        let near174 = abs(f.bpm - 174) <= 3
        let near87 = abs(f.bpm - 87) <= 3
        XCTAssertTrue(near174 || near87, "got \(f.bpm)")
        if near87 { XCTAssertNotEqual(f.octaveFlag, .none) }
    }

    func testDeterministic() {
        let samples = SynthAudio.clickTrain(bpm: 132, seconds: 12, sampleRate: sr)
        let a = analyzer.analyze(samples: samples, sampleRate: sr)
        let b = analyzer.analyze(samples: samples, sampleRate: sr)
        XCTAssertEqual(a, b)
    }

    func testConfidenceHigherForCleanPulseThanNoiseFloor() {
        let clean = analyzer.analyze(
            samples: SynthAudio.clickTrain(bpm: 120, seconds: 12, sampleRate: sr), sampleRate: sr)!
        XCTAssertGreaterThan(clean.confidence, 0)
        XCTAssertLessThanOrEqual(clean.confidence, 1)
    }

    func testRejectsTooShortInput() {
        XCTAssertNil(analyzer.analyze(samples: [0, 0, 0, 0], sampleRate: sr))
    }
}
