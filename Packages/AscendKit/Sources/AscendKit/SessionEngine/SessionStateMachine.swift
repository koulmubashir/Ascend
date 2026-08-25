import Foundation

/// Drives a workout session: exercise -> rest -> next exercise -> done.
///
/// Pure and platform-free, so the iPhone and Watch UIs are thin renderers over
/// the same logic rather than two implementations to keep in step. Timers,
/// haptics and notifications are side effects the caller performs - the engine
/// only says what should happen.
public struct SessionStateMachine: Sendable {

    public enum State: Equatable, Sendable {
        case idle
        /// Performing `setIndex` (0-based) of the exercise at `exerciseIndex`.
        case exercising(exerciseIndex: Int, setIndex: Int)
        /// Resting for `seconds`; the next set is already identified.
        case resting(seconds: Int, nextExerciseIndex: Int, nextSetIndex: Int)
        case complete(finished: Bool)
    }

    public enum Event: Equatable, Sendable {
        case start
        /// A set was finished. Reps and weight are recorded on the session.
        case setCompleted(reps: Int, weightKg: Double?)
        case restElapsed
        case skipRest
        case abandon
    }

    /// Something the caller should do as a result of a transition.
    public enum Effect: Equatable, Sendable {
        case startRestTimer(seconds: Int)
        case cancelRestTimer
        case haptic(Haptic)
        case logSet(exerciseID: UUID, setIndex: Int, reps: Int, weightKg: Double?)
        case sessionFinished(completedAllSets: Bool)
    }

    public enum Haptic: Equatable, Sendable {
        case setDone
        case restOver
        case sessionDone
    }

    public private(set) var state: State
    public let exercises: [PlannedExercise]

    public init(exercises: [PlannedExercise], state: State = .idle) {
        self.exercises = exercises.sorted { $0.orderIndex < $1.orderIndex }
        self.state = state
    }

    /// Applies an event, returning the effects the caller should carry out.
    public mutating func handle(_ event: Event) -> [Effect] {
        switch (state, event) {

        case (.idle, .start):
            guard !exercises.isEmpty else {
                state = .complete(finished: false)
                return [.sessionFinished(completedAllSets: false)]
            }
            state = .exercising(exerciseIndex: 0, setIndex: 0)
            return []

        case let (.exercising(exerciseIndex, setIndex), .setCompleted(reps, weight)):
            let current = exercises[exerciseIndex]
            var effects: [Effect] = [
                .logSet(exerciseID: current.exercise.id,
                        setIndex: setIndex,
                        reps: reps,
                        weightKg: weight),
                .haptic(.setDone)
            ]

            guard let next = advance(from: exerciseIndex, setIndex: setIndex) else {
                state = .complete(finished: true)
                effects.append(.haptic(.sessionDone))
                effects.append(.sessionFinished(completedAllSets: true))
                return effects
            }

            // Moving to the next exercise inside a superset means no rest - the
            // whole point is to run them back to back.
            if staysWithinSuperset(from: exerciseIndex, to: next.exerciseIndex) {
                state = .exercising(exerciseIndex: next.exerciseIndex, setIndex: next.setIndex)
                return effects
            }

            // Rest length comes from the exercise just finished, not the next
            // one - the rest belongs to the effort that was just made.
            let rest = current.restSeconds
            state = .resting(seconds: rest,
                             nextExerciseIndex: next.exerciseIndex,
                             nextSetIndex: next.setIndex)
            effects.append(.startRestTimer(seconds: rest))
            return effects

        case let (.resting(_, nextExerciseIndex, nextSetIndex), .restElapsed):
            state = .exercising(exerciseIndex: nextExerciseIndex, setIndex: nextSetIndex)
            return [.haptic(.restOver)]

        case let (.resting(_, nextExerciseIndex, nextSetIndex), .skipRest):
            state = .exercising(exerciseIndex: nextExerciseIndex, setIndex: nextSetIndex)
            return [.cancelRestTimer]

        case (_, .abandon):
            let wasResting: Bool
            if case .resting = state { wasResting = true } else { wasResting = false }
            state = .complete(finished: false)
            return (wasResting ? [.cancelRestTimer] : []) + [.sessionFinished(completedAllSets: false)]

        default:
            // Any other pairing is a no-op rather than a crash: the Watch and
            // phone can both emit events, and a duplicate arriving late should
            // be ignored, not fatal.
            return []
        }
    }

    /// Next (exercise, set) pair, or nil when the session is finished.
    ///
    /// A standalone exercise is taken to completion before moving on. A
    /// superset instead cycles through its members once per round, so set two
    /// of the first exercise only comes after set one of the last.
    private func advance(from exerciseIndex: Int, setIndex: Int) -> (exerciseIndex: Int, setIndex: Int)? {
        let current = exercises[exerciseIndex]

        if let group = supersetRange(containing: exerciseIndex) {
            if exerciseIndex + 1 < group.upperBound {
                return (exerciseIndex + 1, setIndex)
            }
            // Round finished. Back to the top of the superset for the next set.
            if setIndex + 1 < setsInSuperset(group) {
                return (group.lowerBound, setIndex + 1)
            }
            if group.upperBound < exercises.count {
                return (group.upperBound, 0)
            }
            return nil
        }

        if setIndex + 1 < current.targetSets {
            return (exerciseIndex, setIndex + 1)
        }
        if exerciseIndex + 1 < exercises.count {
            return (exerciseIndex + 1, 0)
        }
        return nil
    }

    /// The contiguous run of exercises sharing a superset tag, or nil when the
    /// exercise stands alone.
    private func supersetRange(containing index: Int) -> Range<Int>? {
        guard let tag = exercises[index].supersetTag else { return nil }

        var lower = index
        while lower > 0, exercises[lower - 1].supersetTag == tag { lower -= 1 }

        var upper = index
        while upper + 1 < exercises.count, exercises[upper + 1].supersetTag == tag { upper += 1 }

        // A tag on a single exercise is not a superset, just a stray label.
        return lower == upper ? nil : lower..<(upper + 1)
    }

    /// Members can disagree on set count; the shortest governs the round so no
    /// exercise is left mid-superset.
    private func setsInSuperset(_ group: Range<Int>) -> Int {
        exercises[group].map(\.targetSets).min() ?? 0
    }

    private func staysWithinSuperset(from: Int, to: Int) -> Bool {
        guard let group = supersetRange(containing: from) else { return false }
        return group.contains(to) && to != group.lowerBound
    }

    // MARK: - Presentation helpers

    public var currentExercise: PlannedExercise? {
        switch state {
        case let .exercising(exerciseIndex, _):
            return exercises[exerciseIndex]
        case let .resting(_, nextExerciseIndex, _):
            return exercises[nextExerciseIndex]
        case .idle, .complete:
            return nil
        }
    }

    /// Regions to highlight on the body map right now.
    public var activeRegions: Set<MuscleRegion> {
        currentExercise?.exercise.regions ?? []
    }

    /// Fraction of all planned sets completed, 0...1.
    public func progress(completedSets: Int) -> Double {
        let total = exercises.reduce(0) { $0 + $1.targetSets }
        guard total > 0 else { return 0 }
        return min(1, Double(completedSets) / Double(total))
    }
}
