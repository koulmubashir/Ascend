import Foundation

/// A notification the app should have registered.
///
/// Deliberately not a `UNNotificationRequest`: keeping this a plain value type
/// means the decision of *what* to notify is testable without a notification
/// centre, and the app layer only has to mirror the result.
public struct PendingNotification: Equatable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// Lead-time reminder before a scheduled workout.
        case upcomingWorkout
        /// Nudge after a workout was missed or left unfinished.
        case missedWorkout
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var body: String
    public var fireDate: Date

    public init(id: String, kind: Kind, title: String, body: String, fireDate: Date) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.fireDate = fireDate
    }
}

public enum NotificationPlanner {

    /// Workouts are dated to midnight, so a time of day is needed before a
    /// "3 hours before" reminder means anything. 18:00 is the default.
    public static let defaultWorkoutHour = 18

    /// How long after a missed workout to nudge, in hours past the workout hour.
    private static let missedNudgeDelayHours = 2

    /// Every notification that should currently be registered.
    ///
    /// This is the complete desired set, not a delta - the caller clears and
    /// re-registers, which keeps things correct after a reschedule without
    /// having to track what was already scheduled.
    public static func notifications(
        for schedule: [ScheduledWorkout],
        leadHours: Double,
        now: Date,
        workoutHour: Int = defaultWorkoutHour,
        calendar: Calendar = .current
    ) -> [PendingNotification] {

        schedule.compactMap { workout in
            guard let start = calendar.date(
                bySettingHour: workoutHour, minute: 0, second: 0,
                of: workout.scheduledDate
            ) else { return nil }

            switch workout.status {
            case .upcoming, .partiallyCompleted:
                if start > now {
                    return upcoming(workout, start: start, leadHours: leadHours, now: now)
                }
                return missed(workout, start: start, now: now, calendar: calendar)

            case .completed, .missed, .rescheduled:
                // Nothing to say about a workout that is done, written off, or
                // whose replacement is already on the calendar.
                return nil
            }
        }
        .sorted { $0.fireDate < $1.fireDate }
    }

    private static func upcoming(
        _ workout: ScheduledWorkout,
        start: Date,
        leadHours: Double,
        now: Date
    ) -> PendingNotification? {
        let fire = start.addingTimeInterval(-leadHours * 3600)
        // A reminder whose lead time has already elapsed is dropped rather than
        // fired immediately - nobody wants a "in 3 hours" alert for a workout
        // starting in 20 minutes.
        guard fire > now else { return nil }

        return PendingNotification(
            id: "upcoming-\(workout.id.uuidString)",
            kind: .upcomingWorkout,
            title: workout.trainingDay.name,
            body: bodyText(for: workout, leadHours: leadHours),
            fireDate: fire
        )
    }

    private static func missed(
        _ workout: ScheduledWorkout,
        start: Date,
        now: Date,
        calendar: Calendar
    ) -> PendingNotification? {
        let fire = start.addingTimeInterval(Double(missedNudgeDelayHours) * 3600)
        guard fire > now else { return nil }

        let partial = workout.status == .partiallyCompleted
        return PendingNotification(
            id: "missed-\(workout.id.uuidString)",
            kind: .missedWorkout,
            title: partial ? "Finish \(workout.trainingDay.name)" : "Missed \(workout.trainingDay.name)",
            body: partial
                ? "You left some sets unfinished. Pick up where you left off."
                : "Still time today, or it moves to your next free day.",
            fireDate: fire
        )
    }

    private static func bodyText(for workout: ScheduledWorkout, leadHours: Double) -> String {
        let groups = workout.trainingDay.groups.map(\.displayName).joined(separator: ", ")
        let when: String
        switch leadHours {
        case ..<1.5:  return groups.isEmpty ? "Starting in an hour." : "\(groups) in an hour."
        case ..<12:   when = "in \(Int(leadHours)) hours"
        default:      when = "later today"
        }
        return groups.isEmpty ? "Workout \(when)." : "\(groups) \(when)."
    }
}
