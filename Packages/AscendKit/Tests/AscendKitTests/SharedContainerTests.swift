import XCTest
@testable import AscendKit

/// The App Group mailbox is how a Lock Screen button or a Siri shortcut reaches
/// the app from another process. It has two rules that matter: a command is
/// delivered at most once, and a stale one is never delivered at all.
final class SharedContainerTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ascend-mailbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        SharedSessionCommands.containerOverride = directory
    }

    override func tearDownWithError() throws {
        SharedSessionCommands.containerOverride = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    // MARK: - Delivery

    func testWrittenCommandIsRead() {
        SharedSessionCommands.write(.skipRest)
        XCTAssertEqual(SharedSessionCommands.take(), .skipRest)
    }

    func testCommandIsDeliveredOnlyOnce() {
        SharedSessionCommands.write(.logSet)
        XCTAssertEqual(SharedSessionCommands.take(), .logSet)
        XCTAssertNil(SharedSessionCommands.take(), "a command must not fire twice")
    }

    func testEmptyMailboxYieldsNothing() {
        XCTAssertNil(SharedSessionCommands.take())
    }

    func testAssociatedValuesSurviveTheRoundTrip() {
        SharedSessionCommands.write(.logWater(330))
        XCTAssertEqual(SharedSessionCommands.take(), .logWater(330))
    }

    func testEveryCommandKindSurvivesTheRoundTrip() {
        let commands: [SharedSessionCommand] = [.skipRest, .logSet, .startWorkout, .logWater(500)]
        for command in commands {
            SharedSessionCommands.write(command)
            XCTAssertEqual(SharedSessionCommands.take(), command)
        }
    }

    /// Only the most recent instruction should survive - pressing a button
    /// twice should not queue two actions.
    func testOnlyTheLatestCommandSurvives() {
        SharedSessionCommands.write(.skipRest)
        SharedSessionCommands.write(.startWorkout)

        XCTAssertEqual(SharedSessionCommands.take(), .startWorkout)
        XCTAssertNil(SharedSessionCommands.take())
    }

    // MARK: - Expiry

    func testStaleCommandIsIgnored() {
        let old = Date().addingTimeInterval(-SharedSessionCommands.expiry - 10)
        SharedSessionCommands.write(.skipRest, issuedAt: old)

        XCTAssertNil(SharedSessionCommands.take(), "a forgotten button press must not act on a later session")
    }

    func testStaleCommandIsAlsoCleared() {
        let old = Date().addingTimeInterval(-SharedSessionCommands.expiry - 10)
        SharedSessionCommands.write(.skipRest, issuedAt: old)

        _ = SharedSessionCommands.take()
        SharedSessionCommands.write(.logSet)
        XCTAssertEqual(SharedSessionCommands.take(), .logSet, "the stale command should not have been left behind")
    }

    func testCommandJustInsideTheWindowStillFires() {
        let recent = Date().addingTimeInterval(-SharedSessionCommands.expiry + 10)
        SharedSessionCommands.write(.logSet, issuedAt: recent)

        XCTAssertEqual(SharedSessionCommands.take(), .logSet)
    }

    func testCorruptMailboxIsSurvivable() throws {
        let url = try XCTUnwrap(SharedSessionCommands.containerURL(named: "session-command.json"))
        try Data("not json".utf8).write(to: url)

        XCTAssertNil(SharedSessionCommands.take())
    }

    // MARK: - Widget snapshot

    func testWidgetSnapshotRoundTrips() {
        let snapshot = WidgetSnapshot(
            workoutName: "Pull",
            dayLabel: "Tomorrow",
            groups: ["Back", "Arms"],
            doneThisWeek: 3,
            totalThisWeek: 5,
            streak: 9
        )
        WidgetSnapshot.write(snapshot)

        XCTAssertEqual(WidgetSnapshot.read(), snapshot)
    }

    func testWidgetSnapshotSurvivesRepeatedReads() {
        WidgetSnapshot.write(.preview)

        XCTAssertEqual(WidgetSnapshot.read(), .preview)
        XCTAssertEqual(WidgetSnapshot.read(), .preview, "the snapshot is state, not a one-shot message")
    }

    func testWidgetSnapshotIsNilBeforeAnythingIsWritten() {
        XCTAssertNil(WidgetSnapshot.read())
    }

    func testWidgetSnapshotOverwrites() {
        WidgetSnapshot.write(.preview)
        let updated = WidgetSnapshot(
            workoutName: "Legs",
            dayLabel: "Today",
            groups: ["Legs"],
            doneThisWeek: 4,
            totalThisWeek: 4,
            streak: 12
        )
        WidgetSnapshot.write(updated)

        XCTAssertEqual(WidgetSnapshot.read(), updated)
    }

    /// The two files share a container and must not tread on each other.
    func testSnapshotAndCommandAreIndependent() {
        WidgetSnapshot.write(.preview)
        SharedSessionCommands.write(.skipRest)

        XCTAssertEqual(SharedSessionCommands.take(), .skipRest)
        XCTAssertEqual(WidgetSnapshot.read(), .preview, "taking a command should not disturb the snapshot")
    }
}
