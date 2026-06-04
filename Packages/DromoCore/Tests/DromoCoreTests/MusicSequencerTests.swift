import XCTest
@testable import DromoCore

@MainActor
final class MusicSequencerTests: XCTestCase {

    func test_selectTrack_selectsClosestBPM() async {
        let library = InMemoryBPMLibrary(tracks: [
            makeTrack("A", bpm: 118),
            makeTrack("B", bpm: 122),
            makeTrack("C", bpm: 120)
        ])
        let crossfader = SpyCrossfader()
        let sequencer = MusicSequencer(library: library, crossfader: crossfader)

        await sequencer.selectTrack(forTargetBPM: 120)

        XCTAssertEqual(sequencer.currentTrack?.id, "C")
        XCTAssertEqual(crossfader.lastTrack?.id, "C")
        XCTAssertEqual(crossfader.crossfadeCallCount, 1)
    }

    func test_selectTrack_doesNotRepeatCurrentTrack() async {
        // X is the closest to 120; once it is playing, re-selecting at the same
        // target must NOT transition again (X is excluded; Y is worse).
        let library = InMemoryBPMLibrary(tracks: [
            makeTrack("X", bpm: 120),
            makeTrack("Y", bpm: 140)
        ])
        let crossfader = SpyCrossfader()
        let clock = MutableClock()
        let sequencer = MusicSequencer(library: library, crossfader: crossfader, now: clock.now)

        await sequencer.selectTrack(forTargetBPM: 120)   // → X
        XCTAssertEqual(sequencer.currentTrack?.id, "X")
        XCTAssertEqual(crossfader.crossfadeCallCount, 1)

        clock.advance(by: 120)                            // past min play duration
        await sequencer.selectTrack(forTargetBPM: 120)   // Y is within ±15 but only ±8 used; Y at 140 is out of ±8

        XCTAssertEqual(sequencer.currentTrack?.id, "X")  // unchanged — no repeat, no downgrade
        XCTAssertEqual(crossfader.crossfadeCallCount, 1)
    }

    func test_selectTrack_respectsMinimumPlayDuration() async {
        let library = InMemoryBPMLibrary(tracks: [
            makeTrack("X", bpm: 120),
            makeTrack("Y", bpm: 140)
        ])
        let crossfader = SpyCrossfader()
        let clock = MutableClock()
        let sequencer = MusicSequencer(library: library, crossfader: crossfader, now: clock.now)

        await sequencer.selectTrack(forTargetBPM: 120)   // → X at t=0
        XCTAssertEqual(sequencer.currentTrack?.id, "X")

        // Target jumps to 140 (Y far better) but only 10s elapsed → must hold X.
        clock.advance(by: 10)
        await sequencer.selectTrack(forTargetBPM: 140)
        XCTAssertEqual(sequencer.currentTrack?.id, "X")
        XCTAssertEqual(crossfader.crossfadeCallCount, 1)

        // After min play duration → switch to Y.
        clock.advance(by: 60)                             // total 70s
        await sequencer.selectTrack(forTargetBPM: 140)
        XCTAssertEqual(sequencer.currentTrack?.id, "Y")
        XCTAssertEqual(crossfader.crossfadeCallCount, 2)
    }

    func test_selectTrack_withNoExactMatch_expandsTolerance() async {
        // Nothing within ±8 of 120, but one track within ±15 (at 132).
        let library = InMemoryBPMLibrary(tracks: [
            makeTrack("Far", bpm: 132)
        ])
        let crossfader = SpyCrossfader()
        let sequencer = MusicSequencer(library: library, crossfader: crossfader)

        await sequencer.selectTrack(forTargetBPM: 120)

        XCTAssertEqual(sequencer.currentTrack?.id, "Far")
        XCTAssertEqual(crossfader.crossfadeCallCount, 1)
    }

    func test_selectTrack_withEmptyLibrary_doesNotCrash() async {
        let library = InMemoryBPMLibrary(tracks: [])
        let crossfader = SpyCrossfader()
        let sequencer = MusicSequencer(library: library, crossfader: crossfader)

        await sequencer.selectTrack(forTargetBPM: 120)

        XCTAssertNil(sequencer.currentTrack)
        XCTAssertEqual(crossfader.crossfadeCallCount, 0)
    }
}
