import XCTest
@testable import GymKit

final class IntakeTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    func testTotalSumsOnlyTheMatchingKindAndDay() {
        let entries = [
            IntakeEntry(kind: .protein, amount: 30, loggedAt: date(20, hour: 9)),
            IntakeEntry(kind: .protein, amount: 25, loggedAt: date(20, hour: 18)),
            IntakeEntry(kind: .water,   amount: 500, loggedAt: date(20)),
            IntakeEntry(kind: .protein, amount: 40, loggedAt: date(21)),
        ]
        XCTAssertEqual(
            IntakeTracker.total(entries, kind: .protein, on: date(20), calendar: calendar), 55
        )
        XCTAssertEqual(
            IntakeTracker.total(entries, kind: .water, on: date(20), calendar: calendar), 500
        )
    }

    func testTotalIsZeroWhenNothingLogged() {
        XCTAssertEqual(
            IntakeTracker.total([], kind: .water, on: date(20), calendar: calendar), 0
        )
    }

    func testProgressClampsAtOneWhenTheGoalIsExceeded() {
        XCTAssertEqual(IntakeTracker.progress(total: 3000, goal: 2500), 1)
    }

    func testProgressIsZeroForAnInvalidGoal() {
        XCTAssertEqual(IntakeTracker.progress(total: 100, goal: 0), 0)
    }

    func testDailyTotalsReturnsOldestFirstAndFillsEmptyDays() {
        let entries = [
            IntakeEntry(kind: .water, amount: 1000, loggedAt: date(20)),
            IntakeEntry(kind: .water, amount: 500, loggedAt: date(22)),
        ]
        let totals = IntakeTracker.dailyTotals(
            entries, kind: .water, endingOn: date(22), days: 3, calendar: calendar
        )
        XCTAssertEqual(totals.map(\.total), [1000, 0, 500])
    }

    func testDailyTotalsHandlesZeroDays() {
        XCTAssertTrue(
            IntakeTracker.dailyTotals([], kind: .water, endingOn: date(20), days: 0,
                                      calendar: calendar).isEmpty
        )
    }

    func testReminderTimesFallInsideTheWakingWindow() {
        let times = IntakeTracker.reminderTimes(wakeHour: 8, sleepHour: 22, count: 4)
        XCTAssertEqual(times.count, 4)
        for time in times {
            let hour = time.hour ?? 0
            XCTAssertGreaterThan(hour, 8, "should not fire the moment you wake")
            XCTAssertLessThan(hour, 22, "should not fire as you go to bed")
        }
        // Spread through the day rather than bunched together.
        let hours = times.compactMap(\.hour)
        XCTAssertEqual(hours, hours.sorted())
        XCTAssertGreaterThan(hours.last! - hours.first!, 4)
    }

    func testReminderTimesAreEmptyForNonsenseWindows() {
        XCTAssertTrue(IntakeTracker.reminderTimes(wakeHour: 22, sleepHour: 8).isEmpty)
        XCTAssertTrue(IntakeTracker.reminderTimes(count: 0).isEmpty)
    }

    func testKindsCarrySensibleUnitsAndPresets() {
        XCTAssertEqual(IntakeKind.protein.unit, "g")
        XCTAssertEqual(IntakeKind.water.unit, "ml")
        for kind in IntakeKind.allCases {
            XCTAssertFalse(kind.presets.isEmpty)
            XCTAssertGreaterThan(kind.defaultGoal, 0)
        }
    }
}
