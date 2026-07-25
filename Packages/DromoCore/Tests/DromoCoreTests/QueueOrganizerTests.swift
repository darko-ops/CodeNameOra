import XCTest
@testable import DromoCore

final class QueueOrganizerTests: XCTestCase {

    private func t(_ id: String, bpm: Double = 0, energy: Double = 0.5) -> Track {
        Track(id: id, title: id, artist: "a", bpm: bpm, energyLevel: energy,
              durationSeconds: 180, provider: .appleMusic)
    }

    func testSeedPinnedFirstAndCountPreserved() {
        let seed = t("seed", bpm: 165)
        let tracks = [t("a", bpm: 140), seed, t("b", bpm: 0), t("c", bpm: 190)]
        for order in QueueOrder.allCases {
            let out = QueueOrganizer.organize(tracks, order: order, seed: seed,
                                              preferences: [:], shuffleSeed: 1)
            XCTAssertEqual(out.first?.id, "seed", "\(order) should pin the seed first")
            XCTAssertEqual(Set(out.map(\.id)), Set(tracks.map(\.id)), "\(order) lost/duped tracks")
            XCTAssertEqual(out.count, tracks.count)
        }
    }

    func testTempoFlowNearestNeighbourFromSeed() {
        let seed = t("seed", bpm: 150)
        let pool = [t("c200", bpm: 200), t("b152", bpm: 152),
                    t("d180", bpm: 180), t("a155", bpm: 155)]
        let out = QueueOrganizer.organize([seed] + pool, order: .tempoFlow,
                                          seed: seed, preferences: [:])
        XCTAssertEqual(out.map(\.id), ["seed", "b152", "a155", "d180", "c200"])
    }

    func testTempoFlowFallsBackToTasteWithoutBPM() {
        let tracks = [t("x"), t("y"), t("z")]   // all unknown BPM
        let out = QueueOrganizer.organize(tracks, order: .tempoFlow, seed: nil,
                                          preferences: ["y": 0.9])
        XCTAssertEqual(out.first?.id, "y")
    }

    func testEnergyArcPeaksInTheMiddle() {
        let tracks = [t("e180", bpm: 180), t("a100", bpm: 100), t("c140", bpm: 140),
                      t("b120", bpm: 120), t("d160", bpm: 160)]
        let out = QueueOrganizer.organize(tracks, order: .energyArc, seed: nil, preferences: [:])
        let peak = out.firstIndex { $0.id == "e180" }!
        XCTAssertGreaterThan(peak, 0)               // not first
        XCTAssertLessThan(peak, out.count - 1)      // not last → it's an arc
    }

    func testTasteOrdersByPreference() {
        let tracks = [t("x"), t("y"), t("z")]
        let out = QueueOrganizer.organize(tracks, order: .taste, seed: nil,
                                          preferences: ["z": 0.9, "x": 0.7, "y": 0.2])
        XCTAssertEqual(out.map(\.id), ["z", "x", "y"])
    }

    func testShuffleIsDeterministicGivenSeed() {
        let tracks = (0..<8).map { t("t\($0)") }
        let a = QueueOrganizer.organize(tracks, order: .shuffle, seed: nil,
                                        preferences: [:], shuffleSeed: 42)
        let b = QueueOrganizer.organize(tracks, order: .shuffle, seed: nil,
                                        preferences: [:], shuffleSeed: 42)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
    }

    func testInOrderKeepsListOrderAfterSeed() {
        let seed = t("seed")
        let tracks = [t("a"), t("b"), seed, t("c")]
        let out = QueueOrganizer.organize(tracks, order: .inOrder, seed: seed, preferences: [:])
        XCTAssertEqual(out.map(\.id), ["seed", "a", "b", "c"])
    }
}
