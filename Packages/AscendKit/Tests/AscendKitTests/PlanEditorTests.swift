import XCTest
@testable import AscendKit

final class PlanEditorTests: XCTestCase {

    private let templateID = UUID()

    private func day(name: String = "Push", sets: Int = 3, isMakeup: Bool = false) -> TrainingDay {
        TrainingDay(
            id: templateID,
            name: name,
            orderInWeek: 0,
            groups: [.chest],
            plannedExercises: [
                PlannedExercise(
                    exercise: Exercise(name: "Bench", group: .chest),
                    orderIndex: 0,
                    targetSets: sets
                )
            ],
            isMakeupDay: isMakeup
        )
    }

    private func workout(
        _ template: TrainingDay,
        day: Int,
        status: ScheduledWorkoutStatus = .upcoming
    ) -> ScheduledWorkout {
        ScheduledWorkout(
            trainingDay: template,
            scheduledDate: Date(timeIntervalSince1970: Double(day) * 86_400),
            status: status
        )
    }

    // MARK: - Series scope

    func testSeriesEditUpdatesTheTemplateAndEveryFutureInstance() {
        let template = day()
        let first = workout(template, day: 1)
        let second = workout(template, day: 8)
        let third = workout(template, day: 15)
        let plan = WorkoutPlan(daysPerWeek: 3, trainingDays: [template])

        let outcome = PlanEditor.apply(
            day(name: "Push A", sets: 5),
            plan: plan,
            schedule: [first, second, third],
            editing: first.id,
            scope: .series
        )

        XCTAssertEqual(outcome.plan?.trainingDays.first?.name, "Push A")
        XCTAssertEqual(outcome.updatedInstances, 2)
        XCTAssertTrue(outcome.schedule.allSatisfy {
            $0.trainingDay.plannedExercises[0].targetSets == 5
        })
    }

    /// The bug this guards: editing one scheduled day used to leave next week's
    /// copy of the same session untouched.
    func testNextWeeksCopyOfTheSameDayIsUpdated() {
        let template = day()
        let thisWeek = workout(template, day: 1)
        let nextWeek = workout(template, day: 8)

        let outcome = PlanEditor.apply(
            day(name: "Renamed"),
            plan: WorkoutPlan(daysPerWeek: 3, trainingDays: [template]),
            schedule: [thisWeek, nextWeek],
            editing: thisWeek.id,
            scope: .series
        )

        XCTAssertEqual(outcome.schedule.last?.trainingDay.name, "Renamed")
    }

    // MARK: - History is left alone

    func testCompletedWorkoutsAreNeverRewritten() {
        let template = day(sets: 3)
        let done = workout(template, day: 1, status: .completed)
        let upcoming = workout(template, day: 8)

        let outcome = PlanEditor.apply(
            day(sets: 5),
            plan: WorkoutPlan(daysPerWeek: 3, trainingDays: [template]),
            schedule: [done, upcoming],
            editing: upcoming.id,
            scope: .series
        )

        // History records what you actually did, not what the plan says now.
        XCTAssertEqual(outcome.schedule.first { $0.id == done.id }?
            .trainingDay.plannedExercises[0].targetSets, 3)
        XCTAssertEqual(outcome.schedule.first { $0.id == upcoming.id }?
            .trainingDay.plannedExercises[0].targetSets, 5)
    }

    func testPartiallyCompletedAndMissedAreAlsoLeftAlone() {
        let template = day(sets: 3)
        let partial = workout(template, day: 1, status: .partiallyCompleted)
        let missed = workout(template, day: 2, status: .missed)
        let upcoming = workout(template, day: 8)

        let outcome = PlanEditor.apply(
            day(sets: 5),
            plan: WorkoutPlan(daysPerWeek: 3, trainingDays: [template]),
            schedule: [partial, missed, upcoming],
            editing: upcoming.id,
            scope: .series
        )
        XCTAssertEqual(outcome.updatedInstances, 0)
    }

    // MARK: - This day only

    func testThisDayOnlyLeavesTheTemplateAndOtherDaysAlone() {
        let template = day(sets: 3)
        let first = workout(template, day: 1)
        let second = workout(template, day: 8)

        let outcome = PlanEditor.apply(
            day(sets: 5),
            plan: WorkoutPlan(daysPerWeek: 3, trainingDays: [template]),
            schedule: [first, second],
            editing: first.id,
            scope: .thisDayOnly
        )

        XCTAssertEqual(outcome.plan?.trainingDays.first?.plannedExercises[0].targetSets, 3)
        XCTAssertEqual(outcome.schedule.first { $0.id == first.id }?
            .trainingDay.plannedExercises[0].targetSets, 5)
        XCTAssertEqual(outcome.schedule.first { $0.id == second.id }?
            .trainingDay.plannedExercises[0].targetSets, 3)
        XCTAssertEqual(outcome.updatedInstances, 0)
    }

    // MARK: - Makeup days

    func testEditingAMakeupDayNeverRewritesTheRecurringTemplate() {
        // A makeup day carries the leftovers of a missed session. Editing it is
        // a one-off, not a change to the plan it came from.
        let template = day(sets: 3)
        let makeup = workout(day(sets: 3, isMakeup: true), day: 3)
        let upcoming = workout(template, day: 8)

        let outcome = PlanEditor.apply(
            day(sets: 5, isMakeup: true),
            plan: WorkoutPlan(daysPerWeek: 3, trainingDays: [template]),
            schedule: [makeup, upcoming],
            editing: makeup.id,
            scope: .series
        )

        XCTAssertEqual(outcome.plan?.trainingDays.first?.plannedExercises[0].targetSets, 3)
        XCTAssertEqual(outcome.updatedInstances, 0)
        XCTAssertEqual(outcome.schedule.first { $0.id == makeup.id }?
            .trainingDay.plannedExercises[0].targetSets, 5)
    }

    func testEditingSurvivesAMissingPlan() {
        let template = day()
        let only = workout(template, day: 1)
        let outcome = PlanEditor.apply(
            day(name: "Solo"), plan: nil, schedule: [only],
            editing: only.id, scope: .series
        )
        XCTAssertNil(outcome.plan)
        XCTAssertEqual(outcome.schedule.first?.trainingDay.name, "Solo")
    }
}
