import XCTest
@testable import AscendKit

final class PlanRecommenderTests: XCTestCase {

    private func answers(
        days: Int = 4,
        experience: PlanRecommender.Experience = .steady,
        equipment: PlanRecommender.Equipment = .fullGym
    ) -> PlanRecommender.Answers {
        .init(daysPerWeek: days, experience: experience, equipment: equipment)
    }

    // MARK: - Splits

    func testSplitMatchesDaysAvailable() {
        XCTAssertEqual(PlanRecommender.recommend(answers(days: 2)).splitName, "Full body")
        XCTAssertEqual(PlanRecommender.recommend(answers(days: 3)).splitName, "Push, pull, legs")
        XCTAssertEqual(PlanRecommender.recommend(answers(days: 4)).splitName, "Upper and lower")
    }

    /// Someone new benefits more from practising each movement often than from
    /// splitting three sessions into thirds.
    func testBeginnersGetFullBodyAtThreeDaysRatherThanASplit() {
        XCTAssertEqual(
            PlanRecommender.recommend(answers(days: 3, experience: .new)).splitName,
            "Full body"
        )
        XCTAssertEqual(
            PlanRecommender.recommend(answers(days: 3, experience: .steady)).splitName,
            "Push, pull, legs"
        )
    }

    // MARK: - Capping

    func testBeginnersAreCappedAtFourDaysEvenIfTheyAskForSix() {
        // Six days in week one is how people stop in week three.
        XCTAssertEqual(PlanRecommender.recommend(answers(days: 6, experience: .new)).daysPerWeek, 4)
    }

    func testReturningLiftersAreCappedAtFive() {
        XCTAssertEqual(
            PlanRecommender.recommend(answers(days: 6, experience: .returning)).daysPerWeek, 5
        )
    }

    func testSteadyLiftersGetWhatTheyAskFor() {
        XCTAssertEqual(PlanRecommender.recommend(answers(days: 6, experience: .steady)).daysPerWeek, 6)
    }

    func testDaysAreClampedToASensibleRange() {
        XCTAssertEqual(PlanRecommender.recommend(answers(days: 0)).daysPerWeek, 2)
        XCTAssertEqual(PlanRecommender.recommend(answers(days: 99)).daysPerWeek, 6)
    }

    // MARK: - Volume

    func testBeginnersGetFewerExercisesAndSets() {
        let new = PlanRecommender.recommend(answers(experience: .new))
        let steady = PlanRecommender.recommend(answers(experience: .steady))
        XCTAssertLessThan(new.exercisesPerDay, steady.exercisesPerDay)
        XCTAssertLessThan(new.setsPerExercise, steady.setsPerExercise)
    }

    func testEveryRecommendationExplainsItself() {
        for days in 2...6 {
            for experience in PlanRecommender.Experience.allCases {
                let r = PlanRecommender.recommend(answers(days: days, experience: experience))
                XCTAssertFalse(r.rationale.isEmpty, "\(days)/\(experience) has no rationale")
                XCTAssertFalse(r.splitName.isEmpty)
            }
        }
    }

    // MARK: - Equipment

    func testBodyweightExcludesBarbellWork() {
        let bench = Exercise(name: "Bench press", group: .chest)
        let pushup = Exercise(name: "Push-up", group: .chest)
        XCTAssertFalse(PlanRecommender.isAvailable(bench, with: .bodyweight))
        XCTAssertTrue(PlanRecommender.isAvailable(pushup, with: .bodyweight))
    }

    func testDumbbellsExcludeCableAndBarbellWork() {
        let cable = Exercise(name: "Cable fly", group: .chest)
        let barbell = Exercise(name: "Barbell row", group: .back)
        let dumbbell = Exercise(name: "Incline dumbbell press", group: .chest)
        XCTAssertFalse(PlanRecommender.isAvailable(cable, with: .dumbbellsOnly))
        XCTAssertFalse(PlanRecommender.isAvailable(barbell, with: .dumbbellsOnly))
        XCTAssertTrue(PlanRecommender.isAvailable(dumbbell, with: .dumbbellsOnly))
    }

    func testFullGymExcludesNothing() {
        for exercise in ExerciseLibrary.starter.all {
            XCTAssertTrue(PlanRecommender.isAvailable(exercise, with: .fullGym))
        }
    }

    func testFilteringNarrowsTheLibraryButNeverEmptiesIt() {
        let full = ExerciseLibrary.starter
        let bodyweight = PlanRecommender.library(full, filteredFor: .bodyweight)
        XCTAssertLessThan(bodyweight.all.count, full.all.count)
        XCTAssertFalse(bodyweight.all.isEmpty, "an empty library would produce an empty plan")
    }

    /// Filtering must never leave nothing to build a plan from - offering an
    /// exercise you can swap beats offering none at all.
    func testAnImpossibleFilterFallsBackToTheFullLibrary() {
        let tiny = ExerciseLibrary(all: [Exercise(name: "Barbell squat", group: .legs)])
        let filtered = PlanRecommender.library(tiny, filteredFor: .bodyweight)
        XCTAssertEqual(filtered.all.count, 1)
    }
}
