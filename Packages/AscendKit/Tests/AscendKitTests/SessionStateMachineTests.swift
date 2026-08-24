import XCTest
@testable import AscendKit

final class SessionStateMachineTests: XCTestCase {

    private func bench() -> Exercise {
        Exercise(name: "Bench press", group: .chest, regions: [.chest, .frontDelt, .triceps],
                 defaultSets: 2, defaultReps: 10, defaultRestSeconds: 90)
    }

    private func row() -> Exercise {
        Exercise(name: "Barbell row", group: .back, regions: [.lats, .biceps],
                 defaultSets: 1, defaultReps: 8, defaultRestSeconds: 60)
    }

    private func machine() -> SessionStateMachine {
        SessionStateMachine(exercises: [
            PlannedExercise(exercise: bench(), orderIndex: 0),
            PlannedExercise(exercise: row(), orderIndex: 1)
        ])
    }

    func testStartMovesToFirstSet() {
        var m = machine()
        XCTAssertTrue(m.handle(.start).isEmpty)
        XCTAssertEqual(m.state, .exercising(exerciseIndex: 0, setIndex: 0))
    }

    func testCompletingSetRestsThenAdvancesWithinSameExercise() {
        var m = machine()
        _ = m.handle(.start)

        let effects = m.handle(.setCompleted(reps: 10, weightKg: 60))
        XCTAssertEqual(m.state, .resting(seconds: 90, nextExerciseIndex: 0, nextSetIndex: 1))
        XCTAssertTrue(effects.contains(.startRestTimer(seconds: 90)))
        XCTAssertTrue(effects.contains(.haptic(.setDone)))

        _ = m.handle(.restElapsed)
        XCTAssertEqual(m.state, .exercising(exerciseIndex: 0, setIndex: 1))
    }

    func testRestUsesFinishedExerciseDurationNotNextOne() {
        var m = machine()
        _ = m.handle(.start)
        _ = m.handle(.setCompleted(reps: 10, weightKg: nil))
        _ = m.handle(.restElapsed)

        // Finishing bench's last set should rest for bench's 90s, even though
        // the next exercise (row) rests for 60s.
        _ = m.handle(.setCompleted(reps: 10, weightKg: nil))
        XCTAssertEqual(m.state, .resting(seconds: 90, nextExerciseIndex: 1, nextSetIndex: 0))
    }

    func testSessionCompletesAfterFinalSet() {
        var m = machine()
        _ = m.handle(.start)
        _ = m.handle(.setCompleted(reps: 10, weightKg: nil))
        _ = m.handle(.restElapsed)
        _ = m.handle(.setCompleted(reps: 10, weightKg: nil))
        _ = m.handle(.restElapsed)

        let effects = m.handle(.setCompleted(reps: 8, weightKg: nil))
        XCTAssertEqual(m.state, .complete(finished: true))
        XCTAssertTrue(effects.contains(.sessionFinished(completedAllSets: true)))
        XCTAssertTrue(effects.contains(.haptic(.sessionDone)))
    }

    func testSkipRestCancelsTimerAndAdvances() {
        var m = machine()
        _ = m.handle(.start)
        _ = m.handle(.setCompleted(reps: 10, weightKg: nil))

        let effects = m.handle(.skipRest)
        XCTAssertEqual(effects, [.cancelRestTimer])
        XCTAssertEqual(m.state, .exercising(exerciseIndex: 0, setIndex: 1))
    }

    func testAbandonMidRestCancelsTimerAndReportsIncomplete() {
        var m = machine()
        _ = m.handle(.start)
        _ = m.handle(.setCompleted(reps: 10, weightKg: nil))

        let effects = m.handle(.abandon)
        XCTAssertEqual(m.state, .complete(finished: false))
        XCTAssertTrue(effects.contains(.cancelRestTimer))
        XCTAssertTrue(effects.contains(.sessionFinished(completedAllSets: false)))
    }

    func testEmptyPlanCompletesImmediately() {
        var m = SessionStateMachine(exercises: [])
        let effects = m.handle(.start)
        XCTAssertEqual(m.state, .complete(finished: false))
        XCTAssertEqual(effects, [.sessionFinished(completedAllSets: false)])
    }

    func testDuplicateEventIsIgnored() {
        var m = machine()
        _ = m.handle(.start)
        _ = m.handle(.setCompleted(reps: 10, weightKg: nil))
        let before = m.state
        // A late duplicate arriving from the other device must not double-advance.
        XCTAssertTrue(m.handle(.setCompleted(reps: 10, weightKg: nil)).isEmpty)
        XCTAssertEqual(m.state, before)
    }

    func testActiveRegionsFollowCurrentExercise() {
        var m = machine()
        _ = m.handle(.start)
        XCTAssertEqual(m.activeRegions, [.chest, .frontDelt, .triceps])

        _ = m.handle(.setCompleted(reps: 10, weightKg: nil))
        _ = m.handle(.restElapsed)
        _ = m.handle(.setCompleted(reps: 10, weightKg: nil))
        // While resting, the map should already show what is coming next.
        XCTAssertEqual(m.activeRegions, [.lats, .biceps])
    }
}
