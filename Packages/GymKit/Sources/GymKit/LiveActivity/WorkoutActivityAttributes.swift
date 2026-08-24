import Foundation

/// Shape of the Lock Screen Live Activity.
///
/// Lives in GymKit because both the app (which starts and updates the activity)
/// and the widget extension (which renders it) need the same definition.
///
/// `ActivityAttributes` conformance is declared in the app and widget targets,
/// which link ActivityKit; GymKit stays free of it so the package still builds
/// for watchOS, where ActivityKit does not exist.
public struct WorkoutActivityState: Codable, Hashable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case exercising
        case resting
    }

    public var phase: Phase
    public var exerciseName: String
    public var setNumber: Int
    public var totalSets: Int
    public var exerciseNumber: Int
    public var totalExercises: Int
    /// When the current rest ends. Nil while exercising.
    ///
    /// Sent as an absolute date rather than a countdown so the Lock Screen can
    /// render a self-updating timer. That matters: iOS throttles how often an
    /// activity may be updated, so pushing a new value every second would be
    /// dropped. One update per state change, and the system ticks the clock.
    public var restEndsAt: Date?
    public var completedSets: Int
    public var totalPlannedSets: Int

    public init(
        phase: Phase,
        exerciseName: String,
        setNumber: Int,
        totalSets: Int,
        exerciseNumber: Int,
        totalExercises: Int,
        restEndsAt: Date? = nil,
        completedSets: Int = 0,
        totalPlannedSets: Int = 0
    ) {
        self.phase = phase
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.totalSets = totalSets
        self.exerciseNumber = exerciseNumber
        self.totalExercises = totalExercises
        self.restEndsAt = restEndsAt
        self.completedSets = completedSets
        self.totalPlannedSets = totalPlannedSets
    }

    public var progress: Double {
        guard totalPlannedSets > 0 else { return 0 }
        return min(1, Double(completedSets) / Double(totalPlannedSets))
    }

    /// Short line for the Dynamic Island's compact presentation.
    public var compactSummary: String {
        switch phase {
        case .exercising: return "Set \(setNumber)/\(totalSets)"
        case .resting:    return "Rest"
        }
    }
}

/// Static, unchanging details of the workout the activity is tracking.
public struct WorkoutActivityInfo: Codable, Hashable, Sendable {
    public var workoutName: String
    public var bodyMapKey: BodyMapKey

    public init(workoutName: String, bodyMapKey: BodyMapKey) {
        self.workoutName = workoutName
        self.bodyMapKey = bodyMapKey
    }
}
