import XCTest
@testable import AscendKit

/// Pairing exercises into supersets, from the plan editor's side.
final class SupersetEditingTests: XCTestCase {

    private func plan(_ tags: [Int?]) -> [PlannedExercise] {
        tags.enumerated().map { index, tag in
            PlannedExercise(
                exercise: Exercise(name: "E\(index)", group: .arms, regions: [.biceps]),
                orderIndex: index,
                supersetTag: tag
            )
        }
    }

    func testJoiningTagsBothExercises() {
        let list = plan([nil, nil])
        let result = PlanEditor.toggleSuperset(list[1].id, in: list)

        XCTAssertNotNil(result[0].supersetTag)
        XCTAssertEqual(result[0].supersetTag, result[1].supersetTag)
    }

    func testJoiningAnExerciseToAnExistingRunReusesItsTag() {
        let list = plan([7, 7, nil])
        let result = PlanEditor.toggleSuperset(list[2].id, in: list)

        XCTAssertEqual(result[2].supersetTag, 7, "should extend the run above, not start a new one")
    }

    func testSeparatingClearsOnlyTheChosenExercise() {
        let list = plan([1, 1])
        let result = PlanEditor.toggleSuperset(list[1].id, in: list)

        XCTAssertEqual(result[0].supersetTag, 1)
        XCTAssertNil(result[1].supersetTag)
    }

    func testSeparatingMidRunRetagsWhatIsBelow() {
        let list = plan([1, 1, 1])
        let result = PlanEditor.toggleSuperset(list[1].id, in: list)

        XCTAssertEqual(result[0].supersetTag, 1)
        XCTAssertNil(result[1].supersetTag)
        XCTAssertNotEqual(result[2].supersetTag, 1, "the tail must not rejoin across the gap")
    }

    func testTheFirstExerciseCannotBeJoinedUpwards() {
        let list = plan([nil, nil])
        let result = PlanEditor.toggleSuperset(list[0].id, in: list)

        XCTAssertEqual(result.map(\.supersetTag), [nil, nil])
    }

    func testUnknownExerciseIsIgnored() {
        let list = plan([nil, nil])
        let result = PlanEditor.toggleSuperset(UUID(), in: list)

        XCTAssertEqual(result.map(\.supersetTag), [nil, nil])
    }

    func testNewTagDoesNotCollideWithExistingOnes() {
        let list = plan([3, 3, nil, nil])
        let result = PlanEditor.toggleSuperset(list[3].id, in: list)

        XCTAssertEqual(result[2].supersetTag, result[3].supersetTag)
        XCTAssertNotEqual(result[2].supersetTag, 3, "a separate pair needs its own tag")
    }

    func testTogglingTwiceReturnsToTheStart() {
        let list = plan([nil, nil])
        let joined = PlanEditor.toggleSuperset(list[1].id, in: list)
        let separated = PlanEditor.toggleSuperset(list[1].id, in: joined)

        XCTAssertNil(separated[1].supersetTag)
    }

    /// The engine only treats a run of two or more as a superset, so the editor
    /// and the engine have to agree on what counts.
    func testAPairedRunIsRecognisedByTheEngine() {
        let list = plan([nil, nil])
        let joined = PlanEditor.toggleSuperset(list[1].id, in: list)

        var machine = SessionStateMachine(exercises: joined)
        _ = machine.handle(.start)
        let effects = machine.handle(.setCompleted(reps: 10, weightKg: 20))

        XCTAssertFalse(
            effects.contains { if case .startRestTimer = $0 { return true } else { return false } },
            "the engine should treat the pair the editor made as a superset"
        )
        XCTAssertEqual(machine.state, .exercising(exerciseIndex: 1, setIndex: 0))
    }

    func testOrderIndicesAreLeftAlone() {
        let list = plan([nil, nil, nil])
        let result = PlanEditor.toggleSuperset(list[1].id, in: list)

        XCTAssertEqual(result.map(\.orderIndex), [0, 1, 2])
    }
}
