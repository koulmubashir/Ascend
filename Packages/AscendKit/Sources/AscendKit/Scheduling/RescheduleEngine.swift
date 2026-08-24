import Foundation

/// Decides what happens to a workout the user missed or left unfinished.
///
/// Pure logic: no persistence, no UI, no HealthKit. Everything it needs arrives
/// as arguments so the whole thing is testable with in-memory fixtures.
public enum RescheduleEngine {

    public struct Outcome: Equatable, Sendable {
        /// The makeup workout to insert, if one could be placed.
        public var makeup: ScheduledWorkout?
        /// New status for the workout that was missed.
        public var originalStatus: ScheduledWorkoutStatus
        public var reason: Reason

        public enum Reason: String, Equatable, Sendable {
            /// Slotted into a free rest day inside the current week.
            case placedInRestDayThisWeek
            /// No rest day left this week; folded into next week's matching day.
            case mergedIntoNextWeek
            /// Nothing left to do - the session was actually finished.
            case nothingOutstanding
            /// Carry-forward budget exhausted; recorded as missed and dropped.
            case abandonedPastCarryForward
        }
    }

    /// How far a missed workout may be chased before it is written off.
    public static let carryForwardLimitDays = 7

    /// - Parameters:
    ///   - missed: the workout that was not completed
    ///   - session: the partial attempt, if the user started one
    ///   - schedule: every other scheduled workout currently on the calendar
    ///   - now: evaluation date
    ///   - calendar: injected so tests are timezone-stable
    public static func plan(
        missed: ScheduledWorkout,
        session: WorkoutSession?,
        schedule: [ScheduledWorkout],
        now: Date,
        calendar: Calendar = .current
    ) -> Outcome {

        let remaining = outstandingExercises(in: missed, session: session)
        guard !remaining.isEmpty else {
            return Outcome(makeup: nil, originalStatus: .completed, reason: .nothingOutstanding)
        }

        // Give up rather than accumulate an endless backlog.
        let anchor = missed.originalDate ?? missed.scheduledDate
        let chased = calendar.dateComponents([.day], from: anchor, to: now).day ?? 0
        if chased > carryForwardLimitDays {
            return Outcome(makeup: nil, originalStatus: .missed, reason: .abandonedPastCarryForward)
        }

        let makeupDay = makeupTrainingDay(from: missed.trainingDay, remaining: remaining)

        if let restDay = nextFreeRestDayThisWeek(after: now, schedule: schedule, calendar: calendar) {
            let makeup = ScheduledWorkout(
                trainingDay: makeupDay,
                scheduledDate: restDay,
                status: .upcoming,
                originalDate: anchor
            )
            return Outcome(makeup: makeup, originalStatus: .rescheduled, reason: .placedInRestDayThisWeek)
        }

        if let slot = nextWeekMatchingDay(for: missed.trainingDay, after: now, schedule: schedule, calendar: calendar) {
            let makeup = ScheduledWorkout(
                trainingDay: makeupDay,
                scheduledDate: slot,
                status: .upcoming,
                originalDate: anchor
            )
            return Outcome(makeup: makeup, originalStatus: .rescheduled, reason: .mergedIntoNextWeek)
        }

        return Outcome(makeup: nil, originalStatus: .missed, reason: .abandonedPastCarryForward)
    }

    // MARK: - Pieces

    /// Planned exercises with at least one set still owing.
    static func outstandingExercises(
        in workout: ScheduledWorkout,
        session: WorkoutSession?
    ) -> [PlannedExercise] {
        guard let session else { return workout.trainingDay.plannedExercises }

        var completedSets: [UUID: Int] = [:]
        for log in session.setLogs {
            completedSets[log.exerciseID, default: 0] += 1
        }

        return workout.trainingDay.plannedExercises.filter { planned in
            completedSets[planned.exerciseID, default: 0] < planned.targetSets
        }
    }

    static func makeupTrainingDay(
        from original: TrainingDay,
        remaining: [PlannedExercise]
    ) -> TrainingDay {
        TrainingDay(
            name: original.isMakeupDay ? original.name : "\(original.name) (makeup)",
            orderInWeek: original.orderInWeek,
            groups: original.groups,
            bodyMapKey: original.bodyMapKey,
            plannedExercises: remaining,
            isMakeupDay: true
        )
    }

    /// The soonest day from tomorrow to the end of this week with nothing on it.
    static func nextFreeRestDayThisWeek(
        after now: Date,
        schedule: [ScheduledWorkout],
        calendar: Calendar
    ) -> Date? {
        guard let weekEnd = endOfWeek(containing: now, calendar: calendar) else { return nil }

        let occupied = Set(schedule
            .filter { $0.status != .rescheduled }
            .map { calendar.startOfDay(for: $0.scheduledDate) })

        var day = calendar.startOfDay(for: now)
        while let next = calendar.date(byAdding: .day, value: 1, to: day), next <= weekEnd {
            day = next
            if !occupied.contains(day) { return day }
        }
        return nil
    }

    /// First day next week already training the same groups, else the first free day.
    static func nextWeekMatchingDay(
        for trainingDay: TrainingDay,
        after now: Date,
        schedule: [ScheduledWorkout],
        calendar: Calendar
    ) -> Date? {
        guard let weekEnd = endOfWeek(containing: now, calendar: calendar),
              let nextWeekEnd = calendar.date(byAdding: .day, value: 7, to: weekEnd)
        else { return nil }

        let wanted = Set(trainingDay.groups)
        let upcoming = schedule
            .filter { $0.status == .upcoming }
            .filter { $0.scheduledDate > weekEnd && $0.scheduledDate <= nextWeekEnd }
            .sorted { $0.scheduledDate < $1.scheduledDate }

        if let match = upcoming.first(where: { !Set($0.trainingDay.groups).isDisjoint(with: wanted) }) {
            return match.scheduledDate
        }

        let occupied = Set(upcoming.map { calendar.startOfDay(for: $0.scheduledDate) })
        var day = calendar.startOfDay(for: weekEnd)
        while let next = calendar.date(byAdding: .day, value: 1, to: day), next <= nextWeekEnd {
            day = next
            if !occupied.contains(day) { return day }
        }
        return nil
    }

    static func endOfWeek(containing date: Date, calendar: Calendar) -> Date? {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
        // dateInterval's end is the start of the next week.
        return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: interval.end))
    }
}
