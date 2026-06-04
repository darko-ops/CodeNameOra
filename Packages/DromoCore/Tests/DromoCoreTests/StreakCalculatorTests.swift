import XCTest
@testable import DromoCore

final class StreakCalculatorTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2   // Monday — pinned for deterministic week boundaries
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testNoSessionsIsZero() {
        XCTAssertEqual(StreakCalculator.weeklyStreak(sessionDates: [], now: day(2026, 6, 1), calendar: cal), 0)
    }

    func testThreeConsecutiveWeeks() {
        let now = day(2026, 6, 1)   // a Monday
        let dates = [day(2026, 6, 1), day(2026, 5, 26), day(2026, 5, 20)]  // this, last, prior weeks
        XCTAssertEqual(StreakCalculator.weeklyStreak(sessionDates: dates, now: now, calendar: cal), 3)
    }

    func testGapBreaksStreak() {
        let now = day(2026, 6, 1)
        // this week + a week three weeks ago (gap in between)
        let dates = [day(2026, 6, 1), day(2026, 5, 11)]
        XCTAssertEqual(StreakCalculator.weeklyStreak(sessionDates: dates, now: now, calendar: cal), 1)
    }

    func testInProgressWeekGetsGrace() {
        // Nothing this week yet, but last + prior weeks active → streak holds at 2.
        let now = day(2026, 6, 3)
        let dates = [day(2026, 5, 26), day(2026, 5, 20)]
        XCTAssertEqual(StreakCalculator.weeklyStreak(sessionDates: dates, now: now, calendar: cal), 2)
    }

    func testFullWeekInactiveResetsToZero() {
        // Last activity was two weeks ago; current + previous week both empty → 0.
        let now = day(2026, 6, 10)
        let dates = [day(2026, 5, 20)]
        XCTAssertEqual(StreakCalculator.weeklyStreak(sessionDates: dates, now: now, calendar: cal), 0)
    }

    func testMultipleSessionsSameWeekCountOnce() {
        let now = day(2026, 6, 1)
        let dates = [day(2026, 6, 1), day(2026, 5, 31), day(2026, 5, 26)]  // 2 this week + 1 last
        XCTAssertEqual(StreakCalculator.weeklyStreak(sessionDates: dates, now: now, calendar: cal), 2)
    }
}
