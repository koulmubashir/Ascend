import XCTest
@testable import AscendKit

/// Supersets run their members back to back and rest once the round is done,
/// rather than resting between every exercise.
final class SupersetTests: XCTestCase {

    private func exercise(_ name: String, group: MuscleGroup = .arms) -> Exercise {
        Exercise(name: name, group: group, regions: [.biceps],
                 defaultSets: 3, defaultReps: 10, defaultRestSeconds: 90)
    }

    private func plan(_ specs: [(String, Int?, Int)]) -> [PlannedExercise] {
        specs.enumerated().map { index, spec in
            PlannedExercise(
                exercise: exercise(spec.0),
                orderIndex: index,
                targetSets: spec.2,
                supersetTag: spec.1
            )
        }
    }

    private func complete(_ machine: inout SessionStateMachine) -> [SessionStateMachine.Effect] {
        machine.handle(.setCompleted(reps: 10, weightKg: 20))
    }

    // MARK: - Traversal

    func testSupersetAlternatesBeforeAdvancingTheSet() {
        var machine = SessionStateMachine(exercises: plan([("Curl", 1, 2), ("Pushdown", 1, 2)]))
        _ = machine.handle(.start)
        XCTAssertEqual(machine.state, .exercising(exerciseIndex: 0, setIndex: 0))

        _ = complete(&machine)
        XCTAssertEqual(machine.state, .exercising(exerciseIndex: 1, setIndex: 0),
                       "should move straight to the partner exercise")

        _ = complete(&machine)
        if case let .resting(_, next, set) = machine.state {
            XCTAssertEqual(next, 0, "next round starts back at the top of the superset")
            XCTAssertEqual(set, 1)
        } else {
            XCTFail("expected rest after the round, got \(machine.state)")
        }
    }

    func testNoRestBetweenSupersetMembers() {
        var machine = SessionStateMachine(exercises: plan([("Curl", 1, 2), ("Pushdown", 1, 2)]))
        _ = machine.handle(.start)

        let effects = complete(&machine)
        XCTAssertFalse(
            effects.contains { if case .startRestTimer = $0 { return true } else { return false } },
            "no rest timer should start inside a superset"
        )
    }

    func testRestStartsAfterTheRoundCompletes() {
        var machine = SessionStateMachine(exercises: plan([("Curl", 1, 2), ("Pushdown", 1, 2)]))
        _ = machine.handle(.start)
        _ = complete(&machine)

        let effects = complete(&machine)
        XCTAssertTrue(
            effects.contains(.startRestTimer(seconds: 90)),
            "the round should end in a rest"
        )
    }

    func testEverySetOfEverySupersetMemberIsReached() {
        var machine = SessionStateMachine(exercises: plan([("Curl", 1, 3), ("Pushdown", 1, 3)]))
        _ = machine.handle(.start)

        var seen: [String] = []
        var guardRail = 0
        while machine.state != .complete(finished: true), guardRail < 50 {
            if case let .exercising(exerciseIndex, setIndex) = machine.state {
                seen.append("\(exerciseIndex)-\(setIndex)")
                _ = complete(&machine)
            } else if case .resting = machine.state {
                _ = machine.handle(.skipRest)
            }
            guardRail += 1
        }

        XCTAssertEqual(seen, ["0-0", "1-0", "0-1", "1-1", "0-2", "1-2"])
        XCTAssertEqual(machine.state, .complete(finished: true))
    }

    func testThreeWaySuperset() {
        var machine = SessionStateMachine(
            exercises: plan([("A", 7, 2), ("B", 7, 2), ("C", 7, 2)])
        )
        _ = machine.handle(.start)

        _ = complete(&machine)
        XCTAssertEqual(machine.state, .exercising(exerciseIndex: 1, setIndex: 0))
        _ = complete(&machine)
        XCTAssertEqual(machine.state, .exercising(exerciseIndex: 2, setIndex: 0))

        _ = complete(&machine)
        if case let .resting(_, next, set) = machine.state {
            XCTAssertEqual(next, 0)
            XCTAssertEqual(set, 1)
        } else {
            XCTFail("expected rest after a three-way round, got \(machine.state)")
        }
    }

    // MARK: - Mixing with ordinary exercises

    func testSupersetHandsOffToTheNextStandaloneExercise() {
        var machine = SessionStateMachine(
            exercises: plan([("Curl", 1, 1), ("Pushdown", 1, 1), ("Squat", nil, 1)])
        )
        _ = machine.handle(.start)
        _ = complete(&machine)
        _ = complete(&machine)

        if case let .resting(_, next, set) = machine.state {
            XCTAssertEqual(next, 2, "should move on to the standalone exercise")
            XCTAssertEqual(set, 0)
        } else {
            XCTFail("expected rest before the standalone exercise, got \(machine.state)")
        }
    }

    func testStandaloneExerciseIsUnaffected() {
        var machine = SessionStateMachine(exercises: plan([("Squat", nil, 2), ("Bench", nil, 2)]))
        _ = machine.handle(.start)

        _ = complete(&machine)
        if case let .resting(_, next, set) = machine.state {
            XCTAssertEqual(next, 0, "a standalone exercise finishes its own sets first")
            XCTAssertEqual(set, 1)
        } else {
            XCTFail("expected rest, got \(machine.state)")
        }
    }

    func testTwoSupersetsAreKeptApart() {
        var machine = SessionStateMachine(
            exercises: plan([("A", 1, 1), ("B", 1, 1), ("C", 2, 1), ("D", 2, 1)])
        )
        _ = machine.handle(.start)
        _ = complete(&machine)
        XCTAssertEqual(machine.state, .exercising(exerciseIndex: 1, setIndex: 0))

        _ = complete(&machine)
        if case let .resting(_, next, _) = machine.state {
            XCTAssertEqual(next, 2, "a different tag is a different superset")
        } else {
            XCTFail("expected rest between the two supersets, got \(machine.state)")
        }
    }

    // MARK: - Degenerate cases

    func testLoneTaggedExerciseBehavesNormally() {
        var machine = SessionStateMachine(exercises: plan([("Curl", 1, 2), ("Squat", nil, 1)]))
        _ = machine.handle(.start)

        _ = complete(&machine)
        if case let .resting(_, next, set) = machine.state {
            XCTAssertEqual(next, 0, "a tag on one exercise is not a superset")
            XCTAssertEqual(set, 1)
        } else {
            XCTFail("expected rest, got \(machine.state)")
        }
    }

    func testUnevenSetCountsUseTheShortestMember() {
        var machine = SessionStateMachine(exercises: plan([("Curl", 1, 3), ("Pushdown", 1, 2)]))
        _ = machine.handle(.start)

        var rounds = 0
        var guardRail = 0
        while machine.state != .complete(finished: true), guardRail < 50 {
            if case .exercising = machine.state {
                _ = complete(&machine)
            } else if case .resting = machine.state {
                rounds += 1
                _ = machine.handle(.skipRest)
            }
            guardRail += 1
        }

        XCTAssertEqual(rounds, 1, "two rounds run, so only one rest sits between them")
        XCTAssertEqual(machine.state, .complete(finished: true))
    }

    func testSessionStillFinishes() {
        var machine = SessionStateMachine(exercises: plan([("A", 1, 2), ("B", 1, 2)]))
        _ = machine.handle(.start)

        var guardRail = 0
        while machine.state != .complete(finished: true), guardRail < 50 {
            if case .exercising = machine.state {
                _ = complete(&machine)
            } else if case .resting = machine.state {
                _ = machine.handle(.restElapsed)
            }
            guardRail += 1
        }
        XCTAssertLessThan(guardRail, 50, "superset traversal must terminate")
    }

    // MARK: - Persistence

    func testPlansSavedBeforeSupersetsStillDecode() throws {
        let legacy = """
        {
          "id": "\(UUID().uuidString)",
          "exercise": {
            "id": "\(UUID().uuidString)",
            "name": "Bench press",
            "group": "chest",
            "regions": ["chest"],
            "defaultSets": 3,
            "defaultReps": 10,
            "defaultRestSeconds": 90,
            "alternateIDs": []
          },
          "orderIndex": 0,
          "targetSets": 3,
          "targetReps": 10,
          "restSeconds": 90
        }
        """
        let decoded = try JSONDecoder().decode(PlannedExercise.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.supersetTag)
        XCTAssertEqual(decoded.targetSets, 3)
    }
}
