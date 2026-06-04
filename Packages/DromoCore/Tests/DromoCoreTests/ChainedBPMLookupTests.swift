import XCTest
@testable import DromoCore

private final class StubLookup: BPMLookup, @unchecked Sendable {
    let result: Double?
    private let lock = NSLock()
    private(set) var called = false
    init(_ result: Double?) { self.result = result }
    func bpm(title: String, artist: String) async -> Double? {
        lock.lock(); called = true; lock.unlock()
        return result
    }
}

final class ChainedBPMLookupTests: XCTestCase {

    func testReturnsFirstHit() async {
        let first = StubLookup(nil)
        let second = StubLookup(128)
        let third = StubLookup(999)
        let chain = ChainedBPMLookup([first, second, third])

        let bpm = await chain.bpm(title: "t", artist: "a")

        XCTAssertEqual(bpm, 128)
        XCTAssertTrue(first.called)
        XCTAssertTrue(second.called)
        XCTAssertFalse(third.called, "short-circuits after the first hit")
    }

    func testReturnsNilWhenAllMiss() async {
        let chain = ChainedBPMLookup([StubLookup(nil), StubLookup(nil)])
        let bpm = await chain.bpm(title: "t", artist: "a")
        XCTAssertNil(bpm)
    }
}
