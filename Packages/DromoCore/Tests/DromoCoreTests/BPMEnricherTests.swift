import XCTest
@testable import DromoCore

private final class FakeLookup: BPMLookup, @unchecked Sendable {
    let byTitle: [String: Double]
    private(set) var calls = 0
    private let lock = NSLock()
    init(_ byTitle: [String: Double]) { self.byTitle = byTitle }
    func bpm(title: String, artist: String) async -> Double? {
        lock.lock(); calls += 1; lock.unlock()
        return byTitle[title]
    }
}

private final class FakeSink: BPMSink, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var stored: [String: Double] = [:]
    func store(bpm: Double, trackID: String) async {
        lock.lock(); stored[trackID] = bpm; lock.unlock()
    }
}

final class BPMEnricherTests: XCTestCase {

    private func item(_ id: String, _ title: String) -> EnrichmentItem {
        EnrichmentItem(trackID: id, title: title, artist: "Artist")
    }

    func testEnrichesOnlyFoundTracks() async {
        let lookup = FakeLookup(["A": 128, "B": 174])   // C unknown
        let sink = FakeSink()
        let enricher = BPMEnricher(lookup: lookup, sink: sink, minIntervalNanos: 0)

        let count = await enricher.enrich([item("1", "A"), item("2", "B"), item("3", "C")])

        XCTAssertEqual(count, 2)
        XCTAssertEqual(sink.stored, ["1": 128, "2": 174])
        XCTAssertEqual(lookup.calls, 3)
    }

    func testRejectsImplausiblyLowBPM() async {
        let sink = FakeSink()
        let enricher = BPMEnricher(lookup: FakeLookup(["A": 40]), sink: sink, minIntervalNanos: 0)
        let count = await enricher.enrich([item("1", "A")])
        XCTAssertEqual(count, 0)
        XCTAssertTrue(sink.stored.isEmpty)
    }

    func testReportsProgressPerItem() async {
        final class Collector: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var updates: [BPMEnricher.Progress] = []
            func add(_ p: BPMEnricher.Progress) { lock.lock(); updates.append(p); lock.unlock() }
        }
        let collector = Collector()
        let enricher = BPMEnricher(lookup: FakeLookup(["A": 128]), sink: FakeSink(), minIntervalNanos: 0)

        _ = await enricher.enrich([item("1", "A"), item("2", "B")]) { collector.add($0) }

        XCTAssertEqual(collector.updates.count, 2)
        XCTAssertEqual(collector.updates.map(\.done), [1, 2])
        XCTAssertEqual(collector.updates.last?.total, 2)
        XCTAssertEqual(collector.updates.last?.enriched, 1)   // only "A" resolved
    }
}
