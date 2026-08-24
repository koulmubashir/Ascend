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

    private static var url: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("watch-face.json")
    }

    public static func write(_ snapshot: WatchFaceSnapshot) {
        guard let url else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }

    public static func read() -> WatchFaceSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WatchFaceSnapshot.self, from: data)
    }
}
