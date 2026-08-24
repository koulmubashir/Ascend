import Foundation
import UserNotifications
import GymKit

/// Mirrors whatever `NotificationPlanner` says into the notification centre.
///
/// The decision of what to notify lives in GymKit and is unit-tested; this only
/// registers the result. Every sync clears and re-registers so a reschedule
/// cannot leave a stale reminder behind.
enum NotificationScheduler {

    private static let restTimerID = "rest-timer"

    // MARK: - Workout reminders

    static func sync(schedule: [ScheduledWorkout], settings: FeatureSettings) {
        let centre = UNUserNotificationCenter.current()

        // Keep any live rest timer - it is not part of the workout plan.
        centre.getPendingNotificationRequests { pending in
            let toRemove = pending.map(\.identifier).filter { $0 != restTimerID }
            centre.removePendingNotificationRequests(withIdentifiers: toRemove)

            guard settings.notificationsEnabled else { return }

            let wanted = NotificationPlanner.notifications(
                for: schedule,
                leadHours: settings.notificationLeadHours,
                now: Date()
            )
            for notification in wanted {
                add(notification, to: centre)
            }
        }
    }

    private static func add(_ notification: PendingNotification, to centre: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: notification.fireDate
        )
        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        centre.add(request)
    }

    // MARK: - Intake reminders

    private static let intakePrefix = "intake-"

    /// Repeating daily prompts to log intake, spread across waking hours.
    ///
    /// Neutral by design: these ask you to record what you had, not to drink or
    /// eat on a schedule. The app tracks, it does not coach.
    static func syncIntakeReminders(settings: FeatureSettings) {
        let centre = UNUserNotificationCenter.current()
        centre.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(intakePrefix) }
            centre.removePendingNotificationRequests(withIdentifiers: stale)

            let nutritionOn = settings.proteinTrackingEnabled || settings.waterTrackingEnabled
            guard settings.notificationsEnabled, nutritionOn, settings.intakeRemindersPerDay > 0
            else { return }

            let times = IntakeTracker.reminderTimes(count: settings.intakeRemindersPerDay)
            for (index, time) in times.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "Log your intake"
                content.body = intakeBody(settings: settings)
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "\(intakePrefix)\(index)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
                )
                centre.add(request)
            }
        }
    }

    private static func intakeBody(settings: FeatureSettings) -> String {
        switch (settings.proteinTrackingEnabled, settings.waterTrackingEnabled) {
        case (true, true):  return "Protein and water so far today."
        case (true, false): return "Protein so far today."
        default:            return "Water so far today."
        }
    }

    // MARK: - Rest timer

    /// Backs the in-app rest countdown with a real notification, because iOS
    /// will suspend the app - and the `Timer` with it - the moment the screen
    /// locks. Phase 2 replaces this with the Watch's own haptic.
    static func scheduleRestFinished(in seconds: Int, nextExercise: String?, enabled: Bool) {
        cancelRestFinished()
        guard enabled, seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = nextExercise.map { "Next: \($0)" } ?? "Back to it."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: restTimerID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(seconds), repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelRestFinished() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [restTimerID])
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
