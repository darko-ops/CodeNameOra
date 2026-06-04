import XCTest
@testable import DromoCore

final class ChromaFingerprinterTests: XCTestCase {

    private let sr = 22_050.0
    private let fp = ChromaFingerprinter()

    func testDeterministic() {
        let s = SynthAudio.sine(hz: 440, seconds: 8, sampleRate: sr)
        XCTAssertEqual(fp.fingerprint(samples: s, sampleRate: sr),
                       fp.fingerprint(samples: s, sampleRate: sr))
    }

    func testGainInvariant() {
        // Two "encodings" differing only in level → same fingerprint (level-blind).
        let quiet = SynthAudio.sine(hz: 440, seconds: 8, sampleRate: sr, amplitude: 0.2)
        let loud = SynthAudio.sine(hz: 440, seconds: 8, sampleRate: sr, amplitude: 0.9)
        XCTAssertEqual(fp.fingerprint(samples: quiet, sampleRate: sr),
                       fp.fingerprint(samples: loud, sampleRate: sr))
    }

    func testDifferentPitchesDiffer() {
        // 440 Hz (A) vs ~523 Hz (C) → different dominant pitch class → different fp.
        let a = fp.fingerprint(samples: SynthAudio.sine(hz: 440, seconds: 8, sampleRate: sr), sampleRate: sr)
        let c = fp.fingerprint(samples: SynthAudio.sine(hz: 523.25, seconds: 8, sampleRate: sr), sampleRate: sr)
        XCTAssertNotNil(a); XCTAssertNotNil(c)
        XCTAssertNotEqual(a, c)
    }

    func testFingerprintShape() {
        let f = fp.fingerprint(samples: SynthAudio.sine(hz: 440, seconds: 8, sampleRate: sr), sampleRate: sr)
        XCTAssertEqual(f?.count, fp.segments)                 // one nibble per segment
        XCTAssertTrue(f?.allSatisfy { $0.isHexDigit } ?? false)
    }

    func testRejectsEmpty() {
        XCTAssertNil(fp.fingerprint(samples: [], sampleRate: sr))
    }
}
