import Foundation

/// What the watch face complication shows.
///
/// Written by the Watch app into its own container, so the complication renders
/// with the phone nowhere nearby.
public struct WatchFaceSnapshot: Codable, Hashable, Sendable {
    public var workoutName: String
    public var dayLabel: String
    public var exerciseCount: Int

    public init(workoutName: String, dayLabel: String, exerciseCount: Int) {
        self.workoutName = workoutName
        self.dayLabel = dayLabel
        self.exerciseCount = exerciseCount
    }

    public static let preview = WatchFaceSnapshot(
        workoutName: "Push", dayLabel: "Today", exerciseCount: 4
    )

    /// The App Group container, not the process's own. A widget extension has
    /// a separate container from its host app, so writing to
    /// applicationSupportDirectory would put the file somewhere the
    /// complication could never read it.
    private static var url: URL? {
        SharedSessionCommands.containerURL(named: "watch-face.json")
    }

    public static func write(_ snapshot: WatchFaceSnapshot) {
        guard let url else { return }
        try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }

    public static func read() -> WatchFaceSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WatchFaceSnapshot.self, from: data)
    }
}
