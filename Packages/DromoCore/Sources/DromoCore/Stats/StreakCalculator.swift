import Foundation

/// Weekly "momentum" streak — consecutive calendar weeks (up to now) with at least
/// one session. Pure + injectable `now`/`calendar` so it's deterministic and testable.
///
/// Grace rule: a fresh week with no run yet doesn't break the streak — if the current
/// week is empty, we anchor on last week, so the streak only resets after a full week
/// of inactivity.
public enum StreakCalculator {

    public static func weeklyStreak(
        sessionDates: [Date],
        now: Date,
        calendar: Calendar = .current
    ) -> Int {
        guard !sessionDates.isEmpty else { return 0 }

        func weekStart(_ date: Date) -> Date? {
            calendar.dateInterval(of: .weekOfYear, for: date)?.start
        }

        let activeWeeks = Set(sessionDates.compactMap(weekStart))
        guard let thisWeek = weekStart(now) else { return 0 }

        // Anchor on this week, or grant the in-progress week some grace by falling
        // back to last week.
        var anchor = thisWeek
        if !activeWeeks.contains(anchor) {
            guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek),
                  activeWeeks.contains(lastWeek) else { return 0 }
            anchor = lastWeek
        }

        var count = 0
        var week: Date? = anchor
        while let w = week, activeWeeks.contains(w) {
            count += 1
            week = calendar.date(byAdding: .weekOfYear, value: -1, to: w)
        }
        return count
    }
}
