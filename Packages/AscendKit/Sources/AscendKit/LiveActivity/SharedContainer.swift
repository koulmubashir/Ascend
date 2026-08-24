import Foundation

/// Values passed between the app and its widget extension.
///
/// These live in AscendKit because both processes need them and an app extension
/// cannot export types back to its host app. They are deliberately plain
/// `Codable` - no ActivityKit or WidgetKit - so the package still builds for
/// watchOS.

/// Instructions handed from the widget extension to the app.
public enum SharedSessionCommand: Codable, Equatable, Sendable {
    case skipRest
    case logSet
    /// From a Siri shortcut - start today's scheduled workout.
    case startWorkout
    /// From a Siri shortcut, in millilitres.
    case logWater(Int)
}

/// One-slot mailbox in the App Group container.
///
/// A file rather than `UserDefaults` because both processes may write and a
/// file write is atomic. Only the most recent command survives, which is what
/// we want: a stale "skip rest" from five minutes ago should not fire when the
/// app next opens.
public enum SharedSessionCommands {

    /// Must match the App Group on the app and widget entitlements.
    public static let appGroup = "group.com.mubashirkoul.Ascend"

    /// Commands older than this are ignored, so a button pressed and forgotten
    /// about cannot act on a later session.
    private static let maxAge: TimeInterval = 120

    private struct Envelope: Codable {
        var command: SharedSessionCommand
        var issuedAt: Date
    }

    static func containerURL(named name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(name)
    }

    public static func write(_ command: SharedSessionCommand) {
        guard let url = containerURL(named: "session-command.json") else { return }
        let envelope = Envelope(command: command, issuedAt: Date())
        try? JSONEncoder().encode(envelope).write(to: url, options: .atomic)
    }

    /// Reads and clears the pending command, if it is recent enough to act on.
    public static func take() -> SharedSessionCommand? {
        guard let url = containerURL(named: "session-command.json"),
              let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return nil }

        try? FileManager.default.removeItem(at: url)
        guard Date().timeIntervalSince(envelope.issuedAt) < maxAge else { return nil }
        return envelope.command
    }
}

/// The handful of fields the home screen widget needs.
///
/// Written by the app whenever the plan changes. Kept separate from the full
/// store so the widget does not decode an entire workout history on every
/// timeline refresh.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public var workoutName: String
    public var dayLabel: String
    public var groups: [String]
    public var doneThisWeek: Int
    public var totalThisWeek: Int
    public var streak: Int

    public init(
        workoutName: String,
        dayLabel: String,
        groups: [String],
        doneThisWeek: Int,
        totalThisWeek: Int,
        streak: Int
    ) {
        self.workoutName = workoutName
        self.dayLabel = dayLabel
        self.groups = groups
        self.doneThisWeek = doneThisWeek
        self.totalThisWeek = totalThisWeek
        self.streak = streak
    }

    public static let preview = WidgetSnapshot(
        workoutName: "Push",
        dayLabel: "Today",
        groups: ["Chest", "Shoulders"],
        doneThisWeek: 2,
        totalThisWeek: 4,
        streak: 5
    )

    public static func write(_ snapshot: WidgetSnapshot) {
        guard let url = SharedSessionCommands.containerURL(named: "widget-snapshot.json") else { return }
        try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }

    public static func read() -> WidgetSnapshot? {
        guard let url = SharedSessionCommands.containerURL(named: "widget-snapshot.json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// ActivityKit conformance, guarded so AscendKit still builds for watchOS.
@available(iOS 16.1, *)
public struct WorkoutActivityAttributes: ActivityAttributes {
    public typealias ContentState = WorkoutActivityState

    public var info: WorkoutActivityInfo

    public init(info: WorkoutActivityInfo) {
        self.info = info
    }
}
#endif
