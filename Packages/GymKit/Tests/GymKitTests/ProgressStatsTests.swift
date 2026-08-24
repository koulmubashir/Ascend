import XCTest
@testable import GymKit

final class ProgressStatsTests: XCTestCase {

    private let exerciseID = UUID()

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    private func log(_ weight: Double?, _ reps: Int, day: Int, hour: Int = 12, id: UUID? = nil) -> SetLog {
        SetLog(exerciseID: id ?? exerciseID, setIndex: 0, reps: reps,
               weightKg: weight, completedAt: date(day, hour: hour))
    }

    // MARK: - Volume

    func testVolumeIsWeightTimesReps() {
        XCTAssertEqual(ProgressStats.volume(of: log(60, 10, day: 1)), 600)
    }

    func testBodyweightSetsContributeNoVolumeRatherThanCountingAsOneKg() {
        XCTAssertEqual(ProgressStats.volume(of: log(nil, 20, day: 1)), 0)
    }

    // MARK: - History

    func testHistoryGroupsSetsByDayNotBySession() {
        // Two sessions on the same day should be one point, not two.
        let logs = [log(60, 10, day: 1, hour: 9), log(70, 8, day: 1, hour: 18)]
        let points = ProgressStats.history(for: exerciseID, in: logs, calendar: calendar)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].topSetWeight, 70)
        XCTAssertEqual(points[0].setCount, 2)
    }

    func testHistoryIsOldestFirstAndIgnoresOtherExercises() {
        let other = UUID()
        let logs = [
            log(80, 5, day: 3),
            log(60, 10, day: 1),
            log(999, 1, day: 2, id: other),
        ]
        let points = ProgressStats.history(for: exerciseID, in: logs, calendar: calendar)
        XCTAssertEqual(points.map(\.topSetWeight), [60, 80])
    }

    func testHistoryIsEmptyForAnUntrainedExercise() {
        XCTAssertTrue(ProgressStats.history(for: UUID(), in: [log(60, 10, day: 1)],
                                            calendar: calendar).isEmpty)
    }

    // MARK: - Trend

    func testTrendIsPercentChangeBetweenFirstAndLast() {
        let points = ProgressStats.history(
            for: exerciseID,
            in: [log(100, 5, day: 1), log(110, 5, day: 8)],
            calendar: calendar
        )
        XCTAssertEqual(ProgressStats.trend(points) ?? 0, 10, accuracy: 0.001)
    }

    func testTrendIsNilWithoutEnoughToCompare() {
        let single = ProgressStats.history(for: exerciseID, in: [log(100, 5, day: 1)],
                                           calendar: calendar)
        XCTAssertNil(ProgressStats.trend(single))
        // Bodyweight only - no weights to compare.
        let bodyweight = ProgressStats.history(
            for: exerciseID, in: [log(nil, 10, day: 1), log(nil, 12, day: 3)], calendar: calendar
        )
        XCTAssertNil(ProgressStats.trend(bodyweight))
    }

    // MARK: - Daily volume

    func testDailyVolumeIncludesUntrainedDaysAsZero() {
        let totals = ProgressStats.dailyVolume(
            [log(50, 10, day: 1), log(50, 10, day: 3)],
            endingOn: date(3), days: 3, calendar: calendar
        )
        XCTAssertEqual(totals.map(\.volume), [500, 0, 500])
    }

    // MARK: - Region volume

    func testVolumeIsAttributedInFullToEveryRegionTrained() {
        let bench = Exercise(name: "Bench", group: .chest, regions: [.chest, .triceps])
        let library = ExerciseLibrary(all: [bench])
        let totals = ProgressStats.volumeByRegion(
            logs: [SetLog(exerciseID: bench.id, setIndex: 0, reps: 10,
                          weightKg: 60, completedAt: date(1))],
            library: library,
            from: date(1, hour: 0),
            to: date(1, hour: 23)
        )
        // Deliberately not divided between the two - the bench genuinely loads
        // both, and splitting would understate each.
        XCTAssertEqual(totals[.chest], 600)
        XCTAssertEqual(totals[.triceps], 600)
    }
}

final class GymMathTests: XCTestCase {

    // MARK: - Plates

    func testPlatesForAnExactlyLoadableWeight() {
        let loading = PlateCalculator.plates(for: 100)
        XCTAssertTrue(loading.isExact)
        XCTAssertEqual(loading.achievedTotal, 100)
        // 40 kg per side: 25 + 15.
        XCTAssertEqual(loading.perSide, [25, 15])
    }

    func testBarAloneNeedsNoPlates() {
        let loading = PlateCalculator.plates(for: 20)
        XCTAssertTrue(loading.perSide.isEmpty)
        XCTAssertTrue(loading.isExact)
    }

    func testTargetBelowTheBarIsNotExact() {
        let loading = PlateCalculator.plates(for: 15)
        XCTAssertTrue(loading.perSide.isEmpty)
        XCTAssertFalse(loading.isExact)
        XCTAssertEqual(loading.achievedTotal, 20)
    }

    func testUnreachableWeightReportsWhatIsActuallyLoadable() {
        // 21 kg cannot be made with 1.25 as the smallest plate.
        let loading = PlateCalculator.plates(for: 21)
        XCTAssertFalse(loading.isExact)
        XCTAssertLessThan(loading.achievedTotal, 21)
    }

    func testPlatesAreHeaviestFirst() {
        let loading = PlateCalculator.plates(for: 140)
        XCTAssertEqual(loading.perSide, loading.perSide.sorted(by: >))
    }

    // MARK: - Warm-ups

    func testHeavyWorkingWeightGetsAThreeStepRamp() {
        let ramp = WarmupPlanner.ramp(to: 100)
        XCTAssertEqual(ramp.count, 3)
        XCTAssertEqual(ramp.map(\.weight), ramp.map(\.weight).sorted())
        XCTAssertTrue(ramp.allSatisfy { $0.weight < 100 })
    }

    func testLightWorkingWeightGetsAShortRamp() {
        XCTAssertLessThanOrEqual(WarmupPlanner.ramp(to: 35).count, 1)
    }

    func testNoRampWhenWorkingAtOrBelowTheBar() {
        XCTAssertTrue(WarmupPlanner.ramp(to: 20).isEmpty)
    }

    func testRampWeightsAreActuallyLoadable() {
        for set in WarmupPlanner.ramp(to: 117.5) {
            XCTAssertTrue(PlateCalculator.plates(for: set.weight).isExact,
                          "\(set.weight) should be loadable with standard plates")
        }
    }

    func testRampNeverRepeatsTheSameWeight() {
        let weights = WarmupPlanner.ramp(to: 45).map(\.weight)
        XCTAssertEqual(weights.count, Set(weights).count)
    }
}
