import XCTest
@testable import AscendKit

final class HealthSyncTests: XCTestCase {

    private let ours = "com.mubashirkoul.Ascend"

    private func imported(
        source: String = "com.strava.Strava",
        at seconds: TimeInterval = 10_000,
        id: UUID = UUID()
    ) -> ImportedWorkout {
        ImportedWorkout(
            healthKitID: id,
            activityName: "Running",
            startedAt: Date(timeIntervalSince1970: seconds),
            duration: 1800,
            sourceName: source
        )
    }

    private func session(at seconds: TimeInterval) -> WorkoutSession {
        WorkoutSession(startedAt: Date(timeIntervalSince1970: seconds))
    }

    // MARK: - The double-counting risk

    /// The whole point: this app writes its own workouts to Health, so reading
    /// them back must not import them again.
    func testOurOwnWorkoutsAreNeverImported() {
        let mine = imported(source: ours)
        let result = HealthSync.newImports(
            from: [mine], ourBundleIdentifier: ours,
            alreadyImported: [], ownSessions: []
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testAlreadyImportedWorkoutsAreNotImportedTwice() {
        let existing = imported()
        let result = HealthSync.newImports(
            from: [existing], ourBundleIdentifier: ours,
            alreadyImported: [existing], ownSessions: []
        )
        XCTAssertTrue(result.isEmpty)
    }

    /// Even if the source name does not match, a workout starting at the same
    /// moment as one of ours is the same session seen from the other side.
    func testAWorkoutOverlappingOurOwnSessionIsRejected() {
        let result = HealthSync.newImports(
            from: [imported(source: "com.apple.health", at: 10_060)],
            ourBundleIdentifier: ours,
            alreadyImported: [],
            ownSessions: [session(at: 10_000)]
        )
        XCTAssertTrue(result.isEmpty, "within two minutes counts as the same workout")
    }

    func testAWorkoutWellClearOfOursIsImported() {
        let result = HealthSync.newImports(
            from: [imported(at: 50_000)],
            ourBundleIdentifier: ours,
            alreadyImported: [],
            ownSessions: [session(at: 10_000)]
        )
        XCTAssertEqual(result.count, 1)
    }

    func testGenuinelyNewExternalWorkoutsComeThrough() {
        let a = imported(at: 20_000), b = imported(at: 30_000)
        let result = HealthSync.newImports(
            from: [a, b], ourBundleIdentifier: ours,
            alreadyImported: [], ownSessions: []
        )
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - Combined history

    func testCombinedHistoryIsNewestFirstAndLabelsTheSource() {
        let entries = HealthSync.combinedHistory(
            ownSessions: [session(at: 10_000)],
            imported: [imported(at: 50_000)]
        )
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.date), entries.map(\.date).sorted(by: >))
        XCTAssertFalse(entries[0].isFromThisApp)
        XCTAssertTrue(entries[1].isFromThisApp)
        XCTAssertNotNil(entries[0].detail, "an outside workout should say where it came from")
        XCTAssertNil(entries[1].detail, "our own needs no attribution")
    }

    func testCombinedHistoryHandlesEitherSideBeingEmpty() {
        XCTAssertEqual(
            HealthSync.combinedHistory(ownSessions: [session(at: 1)], imported: []).count, 1
        )
        XCTAssertEqual(
            HealthSync.combinedHistory(ownSessions: [], imported: [imported()]).count, 1
        )
        XCTAssertTrue(HealthSync.combinedHistory(ownSessions: [], imported: []).isEmpty)
    }

    // MARK: - Measurements

    func testOnlyNewerMeasurementsAreImported() {
        let existing = [BodyMeasurement(kind: .bodyWeight, value: 80,
                                        recordedAt: Date(timeIntervalSince1970: 5_000))]
        let newer = BodyMeasurement(kind: .bodyWeight, value: 79,
                                    recordedAt: Date(timeIntervalSince1970: 9_000))
        let older = BodyMeasurement(kind: .bodyWeight, value: 82,
                                    recordedAt: Date(timeIntervalSince1970: 1_000))

        XCTAssertTrue(HealthSync.shouldImport(newer, existing: existing))
        XCTAssertFalse(HealthSync.shouldImport(older, existing: existing),
                       "Health can return years of history; only newer readings are useful")
    }

    func testImplausibleMeasurementsFromHealthAreRejected() {
        // A unit mix-up elsewhere should not corrupt the chart here.
        let nonsense = BodyMeasurement(kind: .bodyWeight, value: 7.5)
        XCTAssertFalse(HealthSync.shouldImport(nonsense, existing: []))
    }

    func testTheFirstMeasurementOfAKindIsAlwaysImported() {
        let first = BodyMeasurement(kind: .waist, value: 84)
        XCTAssertTrue(HealthSync.shouldImport(first, existing: []))
    }
}
