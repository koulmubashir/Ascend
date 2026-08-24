import XCTest
@testable import AscendKit

final class ProgressiveOverloadEngineTests: XCTestCase {

    private let bench = Exercise(
        name: "Bench press",
        group: .chest,
        defaultSets: 3,
        defaultReps: 10
    )

    private func day(_ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: 1, day: d, hour: 9))!
    }

    // MARK: - Suggestions

    func testNoHistoryFallsBackToExerciseDefaults() {
        let s = ProgressiveOverloadEngine.suggestion(for: bench, history: [])
        XCTAssertEqual(s.rationale, .noHistory)
        XCTAssertNil(s.weight)
        XCTAssertEqual(s.reps, 10)
    }

    func testHittingEveryTargetRepAddsWeight() {
        let history = (0..<3).map {
            SetLog(exerciseID: bench.id, setIndex: $0, reps: 10, weightKg: 60, completedAt: day(5))
        }
        let s = ProgressiveOverloadEngine.suggestion(for: bench, history: history, increment: 2.5)

        XCTAssertEqual(s.rationale, .addWeight)
        XCTAssertEqual(s.weight, 62.5)
        XCTAssertEqual(s.reps, 10)
    }

    func testFallingJustShortBuildsRepsAtTheSameWeight() {
        let history = [
            SetLog(exerciseID: bench.id, setIndex: 0, reps: 9, weightKg: 60, completedAt: day(5)),
            SetLog(exerciseID: bench.id, setIndex: 1, reps: 8, weightKg: 60, completedAt: day(5)),
            SetLog(exerciseID: bench.id, setIndex: 2, reps: 8, weightKg: 60, completedAt: day(5))
        ]
        let s = ProgressiveOverloadEngine.suggestion(for: bench, history: history)

        XCTAssertEqual(s.rationale, .addReps)
        XCTAssertEqual(s.weight, 60)
    }

    func testFallingWellShortHoldsSteady() {
        let history = [
            SetLog(exerciseID: bench.id, setIndex: 0, reps: 5, weightKg: 70, completedAt: day(5)),
            SetLog(exerciseID: bench.id, setIndex: 1, reps: 4, weightKg: 70, completedAt: day(5))
        ]
        let s = ProgressiveOverloadEngine.suggestion(for: bench, history: history)

        XCTAssertEqual(s.rationale, .holdSteady)
        XCTAssertEqual(s.weight, 70)
    }

    func testOnlyTheMostRecentSessionDrivesTheSuggestion() {
        // Strong old session, weak recent one - the recent one should win.
        var history = (0..<3).map {
            SetLog(exerciseID: bench.id, setIndex: $0, reps: 10, weightKg: 80, completedAt: day(1))
        }
        history += [
            SetLog(exerciseID: bench.id, setIndex: 0, reps: 4, weightKg: 60, completedAt: day(9))
        ]

        let s = ProgressiveOverloadEngine.suggestion(for: bench, history: history)
        XCTAssertEqual(s.rationale, .holdSteady)
        XCTAssertEqual(s.weight, 60)
    }

    func testOtherExercisesHistoryIsIgnored() {
        let other = UUID()
        let history = (0..<3).map {
            SetLog(exerciseID: other, setIndex: $0, reps: 10, weightKg: 100, completedAt: day(5))
        }
        let s = ProgressiveOverloadEngine.suggestion(for: bench, history: history)
        XCTAssertEqual(s.rationale, .noHistory)
    }

    // MARK: - Records

    func testFirstEverSetSetsRecordsOnEveryMetric() {
        let logs = [SetLog(exerciseID: bench.id, setIndex: 0, reps: 10, weightKg: 60, completedAt: day(5))]
        let prs = ProgressiveOverloadEngine.newRecords(from: logs, existing: [])

        XCTAssertEqual(Set(prs.map(\.metric)), [.maxWeight, .maxReps, .estimatedOneRepMax])
        XCTAssertEqual(prs.first(where: { $0.metric == .maxWeight })?.value, 60)
    }

    func testMatchingAnExistingRecordIsNotANewRecord() {
        let existing = [
            ProgressiveOverloadEngine.PersonalRecord(
                exerciseID: bench.id, metric: .maxWeight, value: 60, achievedAt: day(1)
            )
        ]
        let logs = [SetLog(exerciseID: bench.id, setIndex: 0, reps: 5, weightKg: 60, completedAt: day(5))]
        let prs = ProgressiveOverloadEngine.newRecords(from: logs, existing: existing)

        XCTAssertFalse(prs.contains { $0.metric == .maxWeight })
    }

    func testBeatingAnExistingRecordIsReported() {
        let existing = [
            ProgressiveOverloadEngine.PersonalRecord(
                exerciseID: bench.id, metric: .maxWeight, value: 60, achievedAt: day(1)
            )
        ]
        let logs = [SetLog(exerciseID: bench.id, setIndex: 0, reps: 5, weightKg: 65, completedAt: day(5))]
        let prs = ProgressiveOverloadEngine.newRecords(from: logs, existing: existing)

        XCTAssertEqual(prs.first(where: { $0.metric == .maxWeight })?.value, 65)
    }

    func testBodyweightSetsStillRecordARepRecord() {
        let logs = [SetLog(exerciseID: bench.id, setIndex: 0, reps: 20, weightKg: nil, completedAt: day(5))]
        let prs = ProgressiveOverloadEngine.newRecords(from: logs, existing: [])

        XCTAssertEqual(prs.map(\.metric), [.maxReps])
        XCTAssertEqual(prs.first?.value, 20)
    }

    func testOneRepMaxEstimateClampsHighRepSets() {
        // Past 12 reps the formula stops inflating.
        let at12 = ProgressiveOverloadEngine.estimatedOneRepMax(weight: 60, reps: 12)
        let at30 = ProgressiveOverloadEngine.estimatedOneRepMax(weight: 60, reps: 30)
        XCTAssertEqual(at12, at30)
    }

    func testZeroRepsGivesZeroEstimate() {
        XCTAssertEqual(ProgressiveOverloadEngine.estimatedOneRepMax(weight: 60, reps: 0), 0)
    }
}
