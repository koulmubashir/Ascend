import Foundation

/// Applies an edit to a training day across the plan template and every
/// upcoming instance of that day.
///
/// The problem this solves: `ScheduledWorkout` embeds a copy of its
/// `TrainingDay`, so editing one scheduled day changed only that day. Next
/// week's copy of the same session was untouched, which is not what anyone
/// means by "edit my Push day".
///
/// Deliberately does not touch completed, missed or rescheduled workouts.
/// History is a record of what you actually did, and rewriting it to match a
/// plan you changed afterwards would be a lie.
public enum PlanEditor {

    public struct Outcome: Equatable, Sendable {
        public var plan: WorkoutPlan?
        public var schedule: [ScheduledWorkout]
        /// How many upcoming instances were updated, for a confirmation.
        public var updatedInstances: Int
    }

    /// Propagates `edited` everywhere it should apply.
    ///
    /// - Parameters:
    ///   - edited: the training day after the user's change
    ///   - plan: the standing plan, whose template is updated in place
    ///   - schedule: every scheduled workout
    ///   - scope: whether to change only the one day or the whole series
    public static func apply(
        _ edited: TrainingDay,
        plan: WorkoutPlan?,
        schedule: [ScheduledWorkout],
        editing workoutID: UUID,
        scope: Scope
    ) -> Outcome {

        var newSchedule = schedule
        var updated = 0

        // The instance the user actually opened always changes.
        if let index = newSchedule.firstIndex(where: { $0.id == workoutID }) {
            newSchedule[index].trainingDay = edited
        }

        guard scope == .series else {
            return Outcome(plan: plan, schedule: newSchedule, updatedInstances: 0)
        }

        // A makeup day is a one-off carrying the leftovers of a missed session.
        // Editing it should never rewrite the recurring template it came from.
        guard !edited.isMakeupDay else {
            return Outcome(plan: plan, schedule: newSchedule, updatedInstances: 0)
        }

        var newPlan = plan
        if let templateIndex = newPlan?.trainingDays.firstIndex(where: { $0.id == edited.id }) {
            newPlan?.trainingDays[templateIndex] = edited
        }

        for index in newSchedule.indices {
            let workout = newSchedule[index]
            guard workout.id != workoutID,
                  workout.trainingDay.id == edited.id,
                  !workout.trainingDay.isMakeupDay,
                  // Only what is still to come. Finishing a workout and then
                  // editing the plan must not retroactively change what the
                  // history says you did.
                  workout.status == .upcoming
            else { continue }

            newSchedule[index].trainingDay = edited
            updated += 1
        }

        return Outcome(plan: newPlan, schedule: newSchedule, updatedInstances: updated)
    }

    public enum Scope: String, Equatable, Sendable {
        /// Just the day the user opened.
        case thisDayOnly
        /// The template and every future instance of it.
        case series
    }
}
