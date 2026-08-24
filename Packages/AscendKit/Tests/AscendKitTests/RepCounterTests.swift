import XCTest
@testable import AscendKit

final class RepCounterTests: XCTestCase {

    private let rate: Double = 50

    /// Synthesises a rep as a raised half-cycle over a quiet baseline.
    private func feedReps(
        _ counter: inout RepCounter,
        count: Int,
        secondsPerRep: Double = 2,
        amplitude: Double = 0.6
    ) -> [RepCounter.Event] {
        var events: [RepCounter.Event] = []
        for _ in 0..<count {
            let samples = Int(secondsPerRep * rate)
            for i in 0..<samples {
                let phase = Double(i) / Double(samples)
                // Movement for the first 60% of the rep, then a pause at
                // lockout - which is what a real repetition looks like, and
                // what gives the baseline a quiet trough to find.
                let value: Double
                if phase < 0.6 {
                    value = 0.05 + amplitude * sin(phase / 0.6 * .pi)
                } else {
                    value = 0.05
                }
                if let event = counter.add(value) { events.append(event) }
            }
        }
        return events
    }

    private func feedQuiet(_ counter: inout RepCounter, seconds: Double) -> [RepCounter.Event] {
        var events: [RepCounter.Event] = []
        for _ in 0..<Int(seconds * rate) {
            if let event = counter.add(0.05) { events.append(event) }
        }
        return events
    }

    func testCountsCleanReps() {
        var counter = RepCounter(configuration: .init(sampleRate: rate))
        _ = feedReps(&counter, count: 8)
        XCTAssertEqual(counter.reps, 8)
    }

    func testIgnoresSmallFidgetingMovements() {
        var counter = RepCounter(configuration: .init(sampleRate: rate))
        // Well under minimumAmplitude - a watch tap, an arm shift.
        _ = feedReps(&counter, count: 10, amplitude: 0.05)
        XCTAssertEqual(counter.reps, 0)
    }

    func testDoesNotDoubleCountASingleSlowRep() {
        var counter = RepCounter(configuration: .init(sampleRate: rate))
        // A deliberately slow press should be one rep, not several as the
        // signal wobbles near its peak.
        _ = feedReps(&counter, count: 1, secondsPerRep: 6)
        XCTAssertEqual(counter.reps, 1)
    }

    func testRejectsRepsFasterThanPhysicallyPlausible() {
        var counter = RepCounter(configuration: .init(sampleRate: rate, minimumRepSeconds: 1.0))
        _ = feedReps(&counter, count: 6, secondsPerRep: 0.3)
        // Some may register, but nowhere near six - the rate limit holds.
        XCTAssertLessThan(counter.reps, 6)
    }

    func testFinishesTheSetAfterMotionStops() {
        var counter = RepCounter(configuration: .init(sampleRate: rate, restAfterSeconds: 3))
        _ = feedReps(&counter, count: 5)
        let events = feedQuiet(&counter, seconds: 4)

        XCTAssertEqual(events.last, .setFinished(reps: 5))
        XCTAssertTrue(counter.isFinished)
    }

    func testDoesNotFinishBeforeTheRestWindowElapses() {
        var counter = RepCounter(configuration: .init(sampleRate: rate, restAfterSeconds: 5))
        _ = feedReps(&counter, count: 3)
        let events = feedQuiet(&counter, seconds: 2)
        XCTAssertFalse(events.contains { if case .setFinished = $0 { return true } else { return false } })
    }

    func testNeverFinishesASetThatNeverStarted() {
        var counter = RepCounter(configuration: .init(sampleRate: rate, restAfterSeconds: 2))
        let events = feedQuiet(&counter, seconds: 30)
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(counter.isFinished)
    }

    func testStopsEmittingOnceFinished() {
        var counter = RepCounter(configuration: .init(sampleRate: rate, restAfterSeconds: 2))
        _ = feedReps(&counter, count: 4)
        _ = feedQuiet(&counter, seconds: 3)
        let after = feedReps(&counter, count: 4)
        XCTAssertTrue(after.isEmpty, "a finished counter should stay finished until reset")
        XCTAssertEqual(counter.reps, 4)
    }

    func testResetClearsEverything() {
        var counter = RepCounter(configuration: .init(sampleRate: rate, restAfterSeconds: 2))
        _ = feedReps(&counter, count: 4)
        _ = feedQuiet(&counter, seconds: 3)
        counter.reset()
        XCTAssertEqual(counter.reps, 0)
        XCTAssertFalse(counter.isFinished)
        _ = feedReps(&counter, count: 2)
        XCTAssertEqual(counter.reps, 2)
    }

    /// A single violent spike should not raise the baseline enough to swallow
    /// the reps that follow - which is why the baseline is a low percentile rather than a mean.
    func testOneViolentSpikeDoesNotSuppressLaterReps() {
        var counter = RepCounter(configuration: .init(sampleRate: rate))
        for _ in 0..<5 { _ = counter.add(6.0) }
        _ = feedReps(&counter, count: 5)
        XCTAssertGreaterThanOrEqual(counter.reps, 4)
    }
}

final class PeriodizationEngineTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day))!
    }

    private let settings = PeriodizationEngine.Settings(isEnabled: true, cycleWeeks: 4)

    func testWeekIndexCountsFromThePlanStart() {
        XCTAssertEqual(PeriodizationEngine.weekIndex(for: date(1), planStart: date(1), calendar: calendar), 0)
        XCTAssertEqual(PeriodizationEngine.weekIndex(for: date(8), planStart: date(1), calendar: calendar), 1)
        XCTAssertEqual(PeriodizationEngine.weekIndex(for: date(22), planStart: date(1), calendar: calendar), 3)
    }

    func testTheFourthWeekOfAFourWeekCycleIsTheDeload() {
        XCTAssertTrue(PeriodizationEngine.isDeloadWeek(date(22), planStart: date(1),
                                                       settings: settings, calendar: calendar))
        XCTAssertFalse(PeriodizationEngine.isDeloadWeek(date(15), planStart: date(1),
                                                        settings: settings, calendar: calendar))
    }

    func testTheFirstWeekIsNeverADeload() {
        // Nothing to recover from yet.
        let weekly = PeriodizationEngine.Settings(isEnabled: true, cycleWeeks: 2)
        XCTAssertFalse(PeriodizationEngine.isDeloadWeek(date(1), planStart: date(1),
                                                        settings: weekly, calendar: calendar))
    }

    func testDisabledMeansNoDeloadEver() {
        let off = PeriodizationEngine.Settings(isEnabled: false)
        XCTAssertFalse(PeriodizationEngine.isDeloadWeek(date(22), planStart: date(1),
                                                        settings: off, calendar: calendar))
        XCTAssertNil(PeriodizationEngine.weeksUntilDeload(from: date(1), planStart: date(1),
                                                          settings: off, calendar: calendar))
    }

    func testDeloadCutsSetsAndWeightButKeepsAtLeastOneSet() {
        let exercise = Exercise(name: "Bench", group: .chest, defaultSets: 3)
        let planned = PlannedExercise(exercise: exercise, orderIndex: 0)

        let adjusted = PeriodizationEngine.adjust(
            planned, on: date(22), planStart: date(1),
            settings: settings, suggestedWeight: 100, calendar: calendar
        )
        XCTAssertTrue(adjusted.isDeload)
        XCTAssertGreaterThanOrEqual(adjusted.sets, 1)
        XCTAssertLessThan(adjusted.sets, planned.targetSets)
        XCTAssertLessThan(adjusted.weight ?? 0, 100)
    }

    func testDeloadWeightIsActuallyLoadable() {
        let planned = PlannedExercise(exercise: Exercise(name: "Squat", group: .legs), orderIndex: 0)
        let adjusted = PeriodizationEngine.adjust(
            planned, on: date(22), planStart: date(1),
            settings: settings, suggestedWeight: 102.5, calendar: calendar
        )
        XCTAssertTrue(PlateCalculator.plates(for: adjusted.weight ?? 0).isExact)
    }

    func testNormalWeekPassesTargetsThroughUnchanged() {
        let planned = PlannedExercise(exercise: Exercise(name: "Bench", group: .chest), orderIndex: 0)
        let adjusted = PeriodizationEngine.adjust(
            planned, on: date(15), planStart: date(1),
            settings: settings, suggestedWeight: 100, calendar: calendar
        )
        XCTAssertFalse(adjusted.isDeload)
        XCTAssertEqual(adjusted.sets, planned.targetSets)
        XCTAssertEqual(adjusted.weight, 100)
    }

    func testWeeksUntilDeloadCountsDown() {
        XCTAssertEqual(PeriodizationEngine.weeksUntilDeload(from: date(22), planStart: date(1),
                                                            settings: settings, calendar: calendar), 0)
        XCTAssertEqual(PeriodizationEngine.weeksUntilDeload(from: date(15), planStart: date(1),
                                                            settings: settings, calendar: calendar), 1)
    }
}

final class BodyMeasurementTests: XCTestCase {

    func testRejectsASlippedDecimalPoint() {
        XCTAssertTrue(MeasurementTracker.isPlausible(75, for: .bodyWeight))
        XCTAssertFalse(MeasurementTracker.isPlausible(7.5, for: .bodyWeight))
        XCTAssertFalse(MeasurementTracker.isPlausible(750, for: .bodyWeight))
    }

    func testLatestAndSeriesOrdering() {
        let old = BodyMeasurement(kind: .bodyWeight, value: 80,
                                  recordedAt: Date(timeIntervalSince1970: 1000))
        let new = BodyMeasurement(kind: .bodyWeight, value: 78,
                                  recordedAt: Date(timeIntervalSince1970: 5000))
        let other = BodyMeasurement(kind: .waist, value: 85,
                                    recordedAt: Date(timeIntervalSince1970: 3000))

        XCTAssertEqual(MeasurementTracker.latest(.bodyWeight, in: [old, new, other])?.value, 78)
        XCTAssertEqual(MeasurementTracker.series(.bodyWeight, in: [new, old]).map(\.value), [80, 78])
    }

    func testChangeIsNilWithoutTwoPoints() {
        let single = [BodyMeasurement(kind: .bodyWeight, value: 80,
                                      recordedAt: Date(timeIntervalSince1970: 1000))]
        XCTAssertNil(MeasurementTracker.change(.bodyWeight, in: single,
                                               since: Date(timeIntervalSince1970: 0)))
    }

    func testChangeIsSignedSoLossReadsNegative() {
        let points = [
            BodyMeasurement(kind: .bodyWeight, value: 80, recordedAt: Date(timeIntervalSince1970: 1000)),
            BodyMeasurement(kind: .bodyWeight, value: 77, recordedAt: Date(timeIntervalSince1970: 5000)),
        ]
        XCTAssertEqual(MeasurementTracker.change(.bodyWeight, in: points,
                                                 since: Date(timeIntervalSince1970: 0)), -3)
    }

    func testTrackedOnlyListsKindsWithData() {
        let all = [BodyMeasurement(kind: .waist, value: 85)]
        XCTAssertEqual(MeasurementTracker.tracked(in: all), [.waist])
    }

    /// Body weight deliberately has no "lower is better" opinion - people cut
    /// and bulk, and the app should not assume which.
    func testBodyWeightCarriesNoDirectionalJudgement() {
        XCTAssertFalse(MeasurementKind.bodyWeight.lowerIsTypicallyBetter)
        XCTAssertTrue(MeasurementKind.bodyFat.lowerIsTypicallyBetter)
    }
}
