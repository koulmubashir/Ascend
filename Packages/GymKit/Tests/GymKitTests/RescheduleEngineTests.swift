import XCTest
@testable import GymKit

final class RescheduleEngineTests: XCTestCase {

    // Fixed calendar so these never depend on the machine's timezone or locale.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }()

    private let bench = Exercise(name: "Bench press", group: .chest)
    private let fly = Exercise(name: "Cable fly", group: .chest)
    private var benchID: UUID { bench.id }
    private var flyID: UUID { fly.id }

    /// Monday 5 Jan 2026 through Sunday 11 Jan 2026.
    private func date(_ day: Int, hour: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
    }

    private func pushDay(sets: Int = 3) -> TrainingDay {
        TrainingDay(
            name: "Push",
            orderInWeek: 0,
            groups: [.chest, .shoulders],
            bodyMapKey: .push,
            plannedExercises: [
                PlannedExercise(exercise: bench, orderIndex: 0, targetSets: sets, targetReps: 10, restSeconds: 90),
                PlannedExercise(exercise: fly, orderIndex: 1, targetSets: sets, targetReps: 12, restSeconds: 60)
            ]
        )
    }

    func testFullyMissedDayLandsOnNextFreeRestDay() {
        // Trains Mon and Thu. Missed Monday, evaluated Tuesday.
        let missed = ScheduledWorkout(trainingDay: pushDay(), scheduledDate: date(5))
        let thursday = ScheduledWorkout(
            trainingDay: TrainingDay(name: "Pull", orderInWeek: 1, groups: [.back], bodyMapKey: .pull),
            scheduledDate: date(8)
        )

        let out = RescheduleEngine.plan(
            missed: missed,
            session: nil,
            schedule: [missed, thursday],
            now: date(6),
            calendar: cal
        )

        XCTAssertEqual(out.reason, .placedInRestDayThisWeek)
        XCTAssertEqual(out.originalStatus, .rescheduled)
        // Wednesday the 7th is the first free day after Tuesday.
        XCTAssertEqual(out.makeup.map { cal.startOfDay(for: $0.scheduledDate) },
                       cal.startOfDay(for: date(7)))
        XCTAssertTrue(out.makeup?.trainingDay.isMakeupDay == true)
    }

    func testMakeupCarriesOnlyTheUnfinishedExercises() {
        let missed = ScheduledWorkout(trainingDay: pushDay(sets: 2), scheduledDate: date(5))
        // Bench fully done (2 sets), flyes untouched.
        let session = WorkoutSession(
            scheduledWorkoutID: missed.id,
            setLogs: [
                SetLog(exerciseID: benchID, setIndex: 0, reps: 10, weightKg: 60, completedAt: date(5)),
                SetLog(exerciseID: benchID, setIndex: 1, reps: 10, weightKg: 60, completedAt: date(5))
            ]
        )

        let out = RescheduleEngine.plan(
            missed: missed,
            session: session,
            schedule: [missed],
            now: date(6),
            calendar: cal
        )

        let carried = out.makeup?.trainingDay.plannedExercises ?? []
        XCTAssertEqual(carried.count, 1)
        XCTAssertEqual(carried.first?.exerciseID, flyID)
    }

    func testFullyCompletedSessionNeedsNoMakeup() {
        let missed = ScheduledWorkout(trainingDay: pushDay(sets: 1), scheduledDate: date(5))
        let session = WorkoutSession(
            scheduledWorkoutID: missed.id,
            setLogs: [
                SetLog(exerciseID: benchID, setIndex: 0, reps: 10, completedAt: date(5)),
                SetLog(exerciseID: flyID, setIndex: 0, reps: 12, completedAt: date(5))
            ]
        )

        let out = RescheduleEngine.plan(
            missed: missed,
            session: session,
            schedule: [missed],
            now: date(6),
            calendar: cal
        )

        XCTAssertEqual(out.reason, .nothingOutstanding)
        XCTAssertEqual(out.originalStatus, .completed)
        XCTAssertNil(out.makeup)
    }

    func testWithNoRestDayLeftItFoldsIntoNextWeeksMatchingDay() {
        // Every remaining day this week is already booked.
        let missed = ScheduledWorkout(trainingDay: pushDay(), scheduledDate: date(5))
        var schedule = [missed]
        for day in 6...11 {
            schedule.append(ScheduledWorkout(
                trainingDay: TrainingDay(name: "Booked", orderInWeek: day, groups: [.legs], bodyMapKey: .legs),
                scheduledDate: date(day)
            ))
        }
        // Next week has a chest day on the 13th.
        let nextChest = ScheduledWorkout(
            trainingDay: TrainingDay(name: "Push", orderInWeek: 0, groups: [.chest], bodyMapKey: .push),
            scheduledDate: date(13)
        )
        schedule.append(nextChest)

        let out = RescheduleEngine.plan(
            missed: missed,
            session: nil,
            schedule: schedule,
            now: date(6),
            calendar: cal
        )

        XCTAssertEqual(out.reason, .mergedIntoNextWeek)
        XCTAssertEqual(out.makeup.map { cal.startOfDay(for: $0.scheduledDate) },
                       cal.startOfDay(for: date(13)))
    }

    func testCarryForwardIsCappedAtOneWeek() {
        let missed = ScheduledWorkout(trainingDay: pushDay(), scheduledDate: date(5))

        // Evaluated nine days later - past the limit.
        let out = RescheduleEngine.plan(
            missed: missed,
            session: nil,
            schedule: [missed],
            now: date(14),
            calendar: cal
        )

        XCTAssertEqual(out.reason, .abandonedPastCarryForward)
        XCTAssertEqual(out.originalStatus, .missed)
        XCTAssertNil(out.makeup)
    }

    func testRescheduledWorkoutsDoNotBlockTheirOwnOldSlot() {
        // A workout already moved away should not count as occupying a day.
        let missed = ScheduledWorkout(trainingDay: pushDay(), scheduledDate: date(5))
        let movedAway = ScheduledWorkout(
            trainingDay: TrainingDay(name: "Old", orderInWeek: 9, groups: [.legs], bodyMapKey: .legs),
            scheduledDate: date(7),
            status: .rescheduled
        )

        let out = RescheduleEngine.plan(
            missed: missed,
            session: nil,
            schedule: [missed, movedAway],
            now: date(6),
            calendar: cal
        )

        XCTAssertEqual(out.makeup.map { cal.startOfDay(for: $0.scheduledDate) },
                       cal.startOfDay(for: date(7)))
    }
}
