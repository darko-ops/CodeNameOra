import XCTest
import DromoCore
@testable import Dromo

/// Cover for the five training zones the Sound tab browses by.
///
/// The windows are a partition, not a list: every tagged track has to land in exactly
/// one zone. A gap would orphan tracks that exist in the library but appear in no zone
/// and match no filter chip — visible in All tracks, missing from the ladder, with
/// nothing to explain the difference.
final class TrainingZoneTests: XCTestCase {

    private var zones: [PlaylistCatalog.Zone] { PlaylistCatalog.zones }

    func test_thereAreFiveZones() {
        XCTAssertEqual(zones.count, 5)
    }

    /// No gaps: each zone starts exactly where the previous one ends.
    func test_windowsAreContiguous() {
        for (lower, upper) in zip(zones, zones.dropFirst()) {
            let message = "\(lower.name) does not hand over cleanly to \(upper.name)"
            XCTAssertEqual(lower.upper, upper.lower, message)
        }
    }

    /// The scale is open at both ends: the first zone starts at 0 and the last never
    /// closes, so no tempo is too slow or too fast to place.
    func test_theScaleIsOpenAtBothEnds() {
        XCTAssertEqual(zones.first?.lower, 0)
        XCTAssertNil(zones.last?.upper, "The top zone must not close, or fast tracks fall off")
    }

    /// Every plausible tempo belongs to exactly one zone — the property that makes the
    /// ladder and the filter chips agree.
    func test_everyTempoLandsInExactlyOneZone() {
        for bpm in stride(from: 1.0, through: 260.0, by: 1.0) {
            let matches = zones.filter { $0.contains(bpm) }
            let names = matches.map(\.name).joined(separator: ", ")
            let message = "\(Int(bpm)) BPM matched \(matches.count) zones: \(names)"
            XCTAssertEqual(matches.count, 1, message)
        }
    }

    /// Untagged tracks have no place on the scale and must not be swept into zone 1.
    func test_untaggedBelongsToNoZone() {
        XCTAssertTrue(zones.allSatisfy { !$0.contains(0) })
        XCTAssertNil(PlaylistCatalog.accent(forBPM: 0))
    }

    /// Harder zone, faster pace — the ladder's whole premise. A non-monotonic pace would
    /// make "pick a harder zone" sometimes mean "run slower".
    func test_paceGetsFasterAsZonesGetHarder() {
        let paces = PlaylistCatalog.playlists(from: Self.libraryCoveringEveryZone)
            .compactMap(\.suggestedPaceSecPerKm)

        XCTAssertEqual(paces.count, 5)
        for (faster, slower) in zip(paces, paces.dropFirst()) {
            XCTAssertGreaterThan(faster, slower,
                                 "Pace must fall as intensity rises: \(paces)")
        }
    }

    /// Zone order follows intensity, so the colour ramp reads as a scale.
    func test_zonesAreOrderedByIntensity() {
        let lowers = zones.map(\.lower)
        XCTAssertEqual(lowers, lowers.sorted(), "Zones must be listed easiest first")
    }

    /// A track sitting exactly on a boundary belongs to the higher zone — the lower
    /// bound is inclusive, the upper exclusive, consistently.
    func test_boundariesResolveUpward() {
        guard let boundary = zones.first?.upper else { return XCTFail("No boundary") }

        let matched = zones.filter { $0.contains(boundary) }

        XCTAssertEqual(matched.count, 1)
        XCTAssertEqual(matched.first?.name, zones[1].name,
                       "A tempo on the boundary belongs to the zone it opens")
    }

    /// Only populated zones become rows, so an empty zone doesn't render as a dead end.
    func test_onlyZonesWithTracksBecomeRows() {
        let onlySlow = [track(bpm: 100), track(bpm: 110)]

        let playlists = PlaylistCatalog.playlists(from: onlySlow)

        XCTAssertEqual(playlists.count, 1)
        XCTAssertEqual(playlists.first?.tracks.count, 2)
    }

    // MARK: - Fixtures

    private func track(bpm: Double) -> Track {
        Track(id: "t\(Int(bpm))", title: "T\(Int(bpm))", artist: "A", bpm: bpm,
              energyLevel: 0.5, durationSeconds: 200, provider: .appleMusic)
    }

    /// One track inside every zone, so `playlists(from:)` yields all five.
    private static var libraryCoveringEveryZone: [Track] {
        PlaylistCatalog.zones.enumerated().map { index, zone in
            // Comfortably inside the window rather than on its edge.
            let bpm = zone.upper.map { (zone.lower + $0) / 2 } ?? zone.lower + 10
            return Track(id: "z\(index)", title: "Z\(index)", artist: "A", bpm: bpm,
                         energyLevel: 0.5, durationSeconds: 200, provider: .appleMusic)
        }
    }
}
