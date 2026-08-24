import XCTest
@testable import GymKit

final class WatchSyncTests: XCTestCase {

    private func snapshot() -> WatchSync.SessionSnapshot {
        WatchSync.SessionSnapshot(
            sessionID: UUID(),
            workoutName: "Push",
            bodyMapKey: .push,
            exercises: [
                WatchSync.ExerciseSnapshot(
                    id: UUID(), name: "Bench press",
                    targetSets: 3, targetReps: 10, restSeconds: 90,
                    regions: [.chest, .frontDelt, .triceps],
                    suggestedWeightKg: 60
                )
            ]
        )
    }

    func testEveryMessageSurvivesARoundTrip() throws {
        let messages: [WatchSync.Message] = [
            .startSession(snapshot()),
            .setCompleted(.init(sessionID: UUID(), exerciseID: UUID(),
                                setIndex: 1, reps: 10, weightKg: 60)),
            .sessionEnded(.init(sessionID: UUID(), completedAllSets: true, setLogs: [])),
            .requestSnapshot,
            .noActiveSession
        ]

        for message in messages {
            let decoded = try WatchSync.decode(try WatchSync.encode(message))
            XCTAssertEqual(decoded, message)
        }
    }

    func testPlanSnapshotSurvivesARoundTrip() throws {
        let plan = WatchSync.PlanSnapshot(
            workouts: [WatchSync.UpcomingWorkout(
                id: UUID(), scheduledDate: Date(timeIntervalSince1970: 5000), snapshot: snapshot()
            )],
            repCountingEnabled: true
        )
        let decoded = try WatchSync.decode(try WatchSync.encode(.planUpdated(plan)))
        guard case let .planUpdated(payload) = decoded else { return XCTFail("wrong case") }
        XCTAssertEqual(payload.workouts.count, 1)
        XCTAssertTrue(payload.repCountingEnabled)
    }

    func testWatchStartedSessionRoundTrips() throws {
        let sessionID = UUID(), workoutID = UUID()
        let decoded = try WatchSync.decode(
            try WatchSync.encode(.watchStartedSession(sessionID: sessionID, workoutID: workoutID))
        )
        XCTAssertEqual(decoded, .watchStartedSession(sessionID: sessionID, workoutID: workoutID))
    }

    func testDictionaryRoundTripMatchesWCSessionShape() throws {
        let message = WatchSync.Message.startSession(snapshot())
        let dictionary = try WatchSync.dictionary(for: message)

        XCTAssertNotNil(dictionary[WatchSync.payloadKey] as? Data)
        XCTAssertEqual(try WatchSync.message(from: dictionary), message)
    }

    func testDecodingADictionaryWithoutThePayloadKeyThrows() {
        XCTAssertThrowsError(try WatchSync.message(from: ["something": "else"]))
    }

    func testSnapshotFromWorkoutCarriesExercisesAndRegions() {
        let bench = Exercise(name: "Bench press", group: .chest,
                             regions: [.chest, .frontDelt, .triceps])
        let workout = ScheduledWorkout(
            trainingDay: TrainingDay(
                name: "Push", orderInWeek: 0, groups: [.chest],
                plannedExercises: [PlannedExercise(exercise: bench, orderIndex: 0)]
            ),
            scheduledDate: Date()
        )

        let snapshot = WatchSync.SessionSnapshot(
            sessionID: UUID(),
            workout: workout,
            suggestions: [bench.id: 62.5]
        )

        XCTAssertEqual(snapshot.workoutName, "Push")
        XCTAssertEqual(snapshot.exercises.count, 1)
        XCTAssertEqual(snapshot.exercises[0].regions, [.chest, .frontDelt, .triceps])
        XCTAssertEqual(snapshot.exercises[0].suggestedWeightKg, 62.5)
    }

    /// A set arriving twice after a reachability blip must be identifiable as
    /// the same set, not logged again.
    func testSetCompletedIsIdentifiableAcrossDuplicates() {
        let sessionID = UUID(), exerciseID = UUID()
        let first = WatchSync.SetCompleted(sessionID: sessionID, exerciseID: exerciseID,
                                           setIndex: 2, reps: 10, weightKg: 60,
                                           completedAt: Date(timeIntervalSince1970: 1000))
        let duplicate = first
        XCTAssertEqual(first, duplicate)

        let nextSet = WatchSync.SetCompleted(sessionID: sessionID, exerciseID: exerciseID,
                                             setIndex: 3, reps: 10, weightKg: 60,
                                             completedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertNotEqual(first, nextSet)
    }

    func testSessionEndedCarriesTheWholeLogForOfflineReplay() throws {
        let sessionID = UUID()
        let logs = (0..<3).map {
            WatchSync.SetCompleted(sessionID: sessionID, exerciseID: UUID(),
                                   setIndex: $0, reps: 10, weightKg: 50)
        }
        let ended = WatchSync.SessionEnded(sessionID: sessionID,
                                           completedAllSets: false, setLogs: logs)
        let decoded = try WatchSync.decode(try WatchSync.encode(.sessionEnded(ended)))

        guard case let .sessionEnded(payload) = decoded else {
            return XCTFail("wrong case")
        }
        XCTAssertEqual(payload.setLogs.count, 3)
        XCTAssertFalse(payload.completedAllSets)
    }
}
