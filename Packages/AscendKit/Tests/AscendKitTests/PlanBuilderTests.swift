import XCTest
@testable import AscendKit

/// PlanBuilder runs on every first launch - it turns the one onboarding answer
/// into the whole plan - so the contract it has to hold is simple: you get the
/// number of days you asked for, and they are spread out rather than stacked.
final class PlanBuilderTests: XCTestCase {

    private let library = ExerciseLibrary.starter

    // MARK: - Day counts

    func testEveryRequestedDayCountProducesThatManyDays() {
        for days in 1...6 {
            let built = PlanBuilder.trainingDays(forDaysPerWeek: days, library: library)
            XCTAssertEqual(built.count, days, "asked for \(days) days a week")
        }
    }

    func testDayCountIsClampedRatherThanTrusted() {
        XCTAssertEqual(PlanBuilder.trainingDays(forDaysPerWeek: 0, library: library).count, 1)
        XCTAssertEqual(PlanBuilder.trainingDays(forDaysPerWeek: -3, library: library).count, 1)
        XCTAssertEqual(PlanBuilder.trainingDays(forDaysPerWeek: 99, library: library).count, 6)
    }

    func testSplitIsDeterministic() {
        let first = PlanBuilder.trainingDays(forDaysPerWeek: 4, library: library)
        let second = PlanBuilder.trainingDays(forDaysPerWeek: 4, library: library)
        XCTAssertEqual(first.map(\.name), second.map(\.name))
        XCTAssertEqual(first.map(\.groups), second.map(\.groups))
    }

    // MARK: - Day contents

    func testEveryDayHasExercisesAndOrderedIndices() {
        for days in 1...6 {
            for day in PlanBuilder.trainingDays(forDaysPerWeek: days, library: library) {
                XCTAssertFalse(day.plannedExercises.isEmpty, "\(day.name) had no exercises")
                XCTAssertEqual(
                    day.plannedExercises.map(\.orderIndex),
                    Array(0..<day.plannedExercises.count),
                    "\(day.name) order indices should be contiguous from zero"
                )
            }
        }
    }

    func testDaysAreOrderedAcrossTheWeek() {
        let built = PlanBuilder.trainingDays(forDaysPerWeek: 5, library: library)
        XCTAssertEqual(built.map(\.orderInWeek), Array(0..<5))
    }

    func testPlannedExercisesMatchTheDaysMuscleGroups() {
        for day in PlanBuilder.trainingDays(forDaysPerWeek: 6, library: library) {
            for planned in day.plannedExercises {
                XCTAssertTrue(
                    day.groups.contains(planned.exercise.group),
                    "\(planned.exercise.name) does not belong to \(day.name)"
                )
            }
        }
    }

    func testPlannedExercisesCarryTheirDefaults() {
        let day = PlanBuilder.trainingDays(forDaysPerWeek: 3, library: library)[0]
        for planned in day.plannedExercises {
            XCTAssertEqual(planned.targetSets, planned.exercise.defaultSets)
            XCTAssertEqual(planned.targetReps, planned.exercise.defaultReps)
            XCTAssertEqual(planned.restSeconds, planned.exercise.defaultRestSeconds)
        }
    }

    // MARK: - Scheduling

    func testScheduleStartsAfterTheGivenDayAndKeepsPlanOrder() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let days = PlanBuilder.trainingDays(forDaysPerWeek: 3, library: library)
        let scheduled = PlanBuilder.schedule(days: days, startingAfter: start)

        XCTAssertEqual(scheduled.count, days.count)
        XCTAssertEqual(scheduled.map(\.trainingDay.name), days.map(\.name))

        let startOfDay = Calendar.current.startOfDay(for: start)
        for workout in scheduled {
            XCTAssertGreaterThan(workout.scheduledDate, startOfDay, "nothing should land on the day you set up")
        }
    }

    func testScheduledDatesAlwaysMoveForward() {
        for days in 1...6 {
            let plan = PlanBuilder.trainingDays(forDaysPerWeek: days, library: library)
            let scheduled = PlanBuilder.schedule(
                days: plan,
                startingAfter: Date(timeIntervalSince1970: 1_700_000_000)
            )
            let dates = scheduled.map(\.scheduledDate)
            XCTAssertEqual(dates, dates.sorted(), "\(days)-day plan scheduled out of order")
            XCTAssertEqual(Set(dates).count, dates.count, "\(days)-day plan double-booked a day")
        }
    }

    /// The point of spreading sessions out is recovery. A four-day plan that
    /// lands on four consecutive days and then rests for three is not the plan
    /// the user asked for.
    func testSessionsAreSpreadAcrossTheWeekRatherThanStacked() {
        let calendar = Calendar.current
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        for days in 2...6 {
            let plan = PlanBuilder.trainingDays(forDaysPerWeek: days, library: library)
            let dates = PlanBuilder.schedule(days: plan, startingAfter: start).map(\.scheduledDate)

            let span = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: dates.first!),
                to: calendar.startOfDay(for: dates.last!)
            ).day ?? 0

            // N sessions crammed into consecutive days span exactly N-1 days,
            // so anything genuinely spread has to reach further than that.
            XCTAssertGreaterThanOrEqual(
                span, days,
                "\(days)-day plan spans only \(span) days - sessions are stacked, not spread"
            )
            XCTAssertLessThan(span, 7, "\(days)-day plan should fit inside one week")
        }
    }

    func testConsecutiveTrainingDaysAreLimited() {
        let calendar = Calendar.current
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        // Four sessions fit in a week with a gap after most of them; a plan
        // that never rests before the last day defeats the split.
        let plan = PlanBuilder.trainingDays(forDaysPerWeek: 4, library: library)
        let dates = PlanBuilder.schedule(days: plan, startingAfter: start).map(\.scheduledDate)

        var longestRun = 1
        var run = 1
        for (previous, next) in zip(dates, dates.dropFirst()) {
            let gap = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: previous),
                to: calendar.startOfDay(for: next)
            ).day ?? 0
            run = gap == 1 ? run + 1 : 1
            longestRun = max(longestRun, run)
        }
        XCTAssertLessThanOrEqual(longestRun, 2, "a four-day plan should not run four days straight")
    }

    func testEmptyPlanSchedulesNothing() {
        XCTAssertTrue(PlanBuilder.schedule(days: [], startingAfter: Date()).isEmpty)
    }

    func testScheduledWorkoutsStartUpcoming() {
        let plan = PlanBuilder.trainingDays(forDaysPerWeek: 4, library: library)
        for workout in PlanBuilder.schedule(days: plan, startingAfter: Date()) {
            XCTAssertEqual(workout.status, .upcoming)
        }
    }
}
