import XCTest
@testable import AscendKit

final class NotificationPlannerTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    private func workout(
        day: Int,
        status: ScheduledWorkoutStatus = .upcoming,
        name: String = "Push",
        groups: [MuscleGroup] = [.chest]
    ) -> ScheduledWorkout {
        ScheduledWorkout(
            trainingDay: TrainingDay(name: name, orderInWeek: 0, groups: groups),
            scheduledDate: date(day),
            status: status
        )
    }

    // MARK: - Upcoming

    func testReminderFiresLeadHoursBeforeTheWorkoutHour() {
        let notifications = NotificationPlanner.notifications(
            for: [workout(day: 20)],
            leadHours: 3,
            now: date(19, hour: 9),
            calendar: calendar
        )
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications[0].kind, .upcomingWorkout)
        // Workout hour is 18:00, so a 3 hour lead means 15:00 the same day.
        XCTAssertEqual(notifications[0].fireDate, date(20, hour: 15))
    }

    func testReminderIsDroppedOnceItsLeadTimeHasPassed() {
        // Workout at 18:00 on the 20th, now 17:00 on the 20th - the 3 hour
        // reminder is already stale and should not fire late.
        let notifications = NotificationPlanner.notifications(
            for: [workout(day: 20)],
            leadHours: 3,
            now: date(20, hour: 17),
            calendar: calendar
        )
        XCTAssertTrue(notifications.filter { $0.kind == .upcomingWorkout }.isEmpty)
    }

    func testReminderBodyNamesTheMuscleGroups() {
        let notifications = NotificationPlanner.notifications(
            for: [workout(day: 20, groups: [.chest, .arms])],
            leadHours: 3,
            now: date(19),
            calendar: calendar
        )
        XCTAssertTrue(notifications[0].body.contains("Chest"))
        XCTAssertTrue(notifications[0].body.contains("Arms"))
    }

    // MARK: - Missed

    func testPastUpcomingWorkoutProducesMissedNudge() {
        let notifications = NotificationPlanner.notifications(
            for: [workout(day: 20)],
            leadHours: 3,
            now: date(20, hour: 19),
            calendar: calendar
        )
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications[0].kind, .missedWorkout)
        XCTAssertEqual(notifications[0].fireDate, date(20, hour: 20))
    }

    func testPartiallyCompletedWorkoutAsksYouToFinishIt() {
        let notifications = NotificationPlanner.notifications(
            for: [workout(day: 20, status: .partiallyCompleted)],
            leadHours: 3,
            now: date(20, hour: 19),
            calendar: calendar
        )
        XCTAssertEqual(notifications.first?.kind, .missedWorkout)
        XCTAssertTrue(notifications[0].title.hasPrefix("Finish"))
    }

    func testMissedNudgeIsDroppedOnceItsOwnWindowHasPassed() {
        let notifications = NotificationPlanner.notifications(
            for: [workout(day: 20)],
            leadHours: 3,
            now: date(21, hour: 9),
            calendar: calendar
        )
        XCTAssertTrue(notifications.isEmpty)
    }

    // MARK: - Statuses that stay quiet

    func testCompletedRescheduledAndMissedProduceNothing() {
        for status in [ScheduledWorkoutStatus.completed, .rescheduled, .missed] {
            let notifications = NotificationPlanner.notifications(
                for: [workout(day: 20, status: status)],
                leadHours: 3,
                now: date(19),
                calendar: calendar
            )
            XCTAssertTrue(notifications.isEmpty, "\(status.rawValue) should be silent")
        }
    }

    // MARK: - Set shape

    func testIdsAreStableAndUniquePerWorkout() {
        let a = workout(day: 20)
        let b = workout(day: 22)
        let notifications = NotificationPlanner.notifications(
            for: [a, b],
            leadHours: 3,
            now: date(19),
            calendar: calendar
        )
        XCTAssertEqual(Set(notifications.map(\.id)).count, notifications.count)
        XCTAssertTrue(notifications.contains { $0.id == "upcoming-\(a.id.uuidString)" })
    }

    func testResultIsSortedByFireDate() {
        let notifications = NotificationPlanner.notifications(
            for: [workout(day: 24), workout(day: 20), workout(day: 22)],
            leadHours: 3,
            now: date(19),
            calendar: calendar
        )
        XCTAssertEqual(notifications, notifications.sorted { $0.fireDate < $1.fireDate })
    }
}
