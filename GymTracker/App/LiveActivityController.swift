import Foundation
import GymKit
#if canImport(ActivityKit)
import ActivityKit
#endif
import WidgetKit

/// Starts, updates and ends the Lock Screen Live Activity.
///
/// Updates are pushed only on real state changes - a new exercise, rest
/// starting or ending. The countdown itself is rendered by the system from
/// `restEndsAt`, because iOS budgets activity updates and a per-second push
/// would simply be dropped.
@MainActor
final class LiveActivityController: ObservableObject {

    #if canImport(ActivityKit)
    /// Held as Any because the concrete generic type is iOS 16.1+ and this
    /// class is not.
    private var storedActivity: Any?

    @available(iOS 16.2, *)
    private var activity: Activity<WorkoutActivityAttributes>? {
        get { storedActivity as? Activity<WorkoutActivityAttributes> }
        set { storedActivity = newValue }
    }
    #endif

    static var isSupported: Bool {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        #endif
        return false
    }

    func start(workoutName: String, bodyMapKey: BodyMapKey, state: WorkoutActivityState) {
        #if canImport(ActivityKit)
        // request/update/end are 16.2, a notch above ActivityConfiguration's 16.1.
        guard #available(iOS 16.2, *), Self.isSupported, storedActivity == nil else { return }
        let attributes = WorkoutActivityAttributes(
            info: WorkoutActivityInfo(workoutName: workoutName, bodyMapKey: bodyMapKey)
        )
        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil)
        )
        #endif
    }

    func update(_ state: WorkoutActivityState) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *), let activity else { return }
        Task { await activity.update(.init(state: state, staleDate: nil)) }
        #endif
    }

    func end() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *), let activity else { return }
        let finished = activity
        self.activity = nil
        Task { await finished.end(nil, dismissalPolicy: .immediate) }
        #endif
    }

    /// Nudges the home screen widget after anything that changes what it shows.
    static func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "NextWorkout")
    }
}
