import Foundation

/// Value types for the planning and session model.
///
/// These are deliberately persistence-agnostic. Core Data entities map to and
/// from them at the edges, which keeps the engines pure and testable without a
/// managed object context - and therefore without Xcode.

// MARK: - Reference data

public struct Exercise: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    /// The group this exercise is filed under when building a plan.
    public var group: MuscleGroup
    /// The regions it actually trains, used to drive the body map.
    public var regions: Set<MuscleRegion>
    public var defaultSets: Int
    public var defaultReps: Int
    public var defaultRestSeconds: Int
    /// Exercises that train overlapping regions, offered as substitutions.
    public var alternateIDs: [UUID]

    public init(
        id: UUID = UUID(),
        name: String,
        group: MuscleGroup,
        /// Defaults to the group's regions when an exercise has not been
        /// tagged individually, so seed content can be added without pinning
        /// down anatomy first.
        regions: Set<MuscleRegion>? = nil,
        defaultSets: Int = 3,
        defaultReps: Int = 10,
        defaultRestSeconds: Int = 90,
        alternateIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.regions = regions ?? group.regions
        self.defaultSets = defaultSets
        self.defaultReps = defaultReps
        self.defaultRestSeconds = defaultRestSeconds
        self.alternateIDs = alternateIDs
    }
}

// MARK: - Plan template

public struct PlannedExercise: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var exercise: Exercise
    public var orderIndex: Int
    public var targetSets: Int
    public var targetReps: Int
    public var restSeconds: Int

    public init(
        id: UUID = UUID(),
        exercise: Exercise,
        orderIndex: Int,
        targetSets: Int? = nil,
        targetReps: Int? = nil,
        restSeconds: Int? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.orderIndex = orderIndex
        self.targetSets = targetSets ?? exercise.defaultSets
        self.targetReps = targetReps ?? exercise.defaultReps
        self.restSeconds = restSeconds ?? exercise.defaultRestSeconds
    }

    public var exerciseID: UUID { exercise.id }
}

/// A day in the weekly template. Never mutated by rescheduling - only
/// `ScheduledWorkout` moves.
public struct TrainingDay: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var orderInWeek: Int
    /// Groups this day is planned around. Drives which exercises get pulled in
    /// and which makeup day a missed session can fold into.
    public var groups: [MuscleGroup]
    /// The artwork to show. Defaults to the best match for `groups` but is
    /// stored rather than derived, so a hand-picked image survives edits.
    public var bodyMapKey: BodyMapKey
    public var plannedExercises: [PlannedExercise]
    /// True when this day was synthesised to make up a missed session.
    public var isMakeupDay: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        orderInWeek: Int,
        groups: [MuscleGroup],
        bodyMapKey: BodyMapKey? = nil,
        plannedExercises: [PlannedExercise] = [],
        isMakeupDay: Bool = false
    ) {
        self.id = id
        self.name = name
        self.orderInWeek = orderInWeek
        self.groups = groups
        self.plannedExercises = plannedExercises
        self.isMakeupDay = isMakeupDay
        self.bodyMapKey = bodyMapKey ?? BodyMapKey.bestMatch(
            for: groups.reduce(into: Set<MuscleRegion>()) { $0.formUnion($1.regions) }
        )
    }

    /// Regions actually trained, taken from the exercises rather than the
    /// groups, so a substitution changes what the map highlights.
    public var regions: Set<MuscleRegion> {
        plannedExercises.reduce(into: Set<MuscleRegion>()) { $0.formUnion($1.exercise.regions) }
    }
}

public struct WorkoutPlan: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var daysPerWeek: Int
    public var trainingDays: [TrainingDay]
    public var notificationLeadHours: Double
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        daysPerWeek: Int,
        trainingDays: [TrainingDay],
        notificationLeadHours: Double = 3,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.daysPerWeek = daysPerWeek
        self.trainingDays = trainingDays
        self.notificationLeadHours = notificationLeadHours
        self.createdAt = createdAt
    }
}

// MARK: - Calendar instances

public enum ScheduledWorkoutStatus: String, Codable, Sendable {
    case upcoming
    case completed
    case partiallyCompleted
    case missed
    case rescheduled
}

public struct ScheduledWorkout: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var trainingDay: TrainingDay
    public var scheduledDate: Date
    public var status: ScheduledWorkoutStatus
    /// Set when this instance was moved, for the audit trail.
    public var originalDate: Date?

    public init(
        id: UUID = UUID(),
        trainingDay: TrainingDay,
        scheduledDate: Date,
        status: ScheduledWorkoutStatus = .upcoming,
        originalDate: Date? = nil
    ) {
        self.id = id
        self.trainingDay = trainingDay
        self.scheduledDate = scheduledDate
        self.status = status
        self.originalDate = originalDate
    }
}

// MARK: - Session records

public struct SetLog: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var exerciseID: UUID
    public var setIndex: Int
    public var reps: Int
    public var weightKg: Double?
    public var completedAt: Date

    public init(
        id: UUID = UUID(),
        exerciseID: UUID,
        setIndex: Int,
        reps: Int,
        weightKg: Double? = nil,
        completedAt: Date = Date()
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.setIndex = setIndex
        self.reps = reps
        self.weightKg = weightKg
        self.completedAt = completedAt
    }
}

public struct WorkoutSession: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var scheduledWorkoutID: UUID?
    public var startedAt: Date
    public var endedAt: Date?
    public var totalActiveSeconds: Double
    public var totalRestSeconds: Double
    public var isComplete: Bool
    public var setLogs: [SetLog]
    /// Free text against the session - "shoulder twinge", "felt easy". Worth a
    /// lot when reading history back months later.
    public var notes: String?

    public init(
        id: UUID = UUID(),
        scheduledWorkoutID: UUID? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        totalActiveSeconds: Double = 0,
        totalRestSeconds: Double = 0,
        isComplete: Bool = false,
        setLogs: [SetLog] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.scheduledWorkoutID = scheduledWorkoutID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.totalActiveSeconds = totalActiveSeconds
        self.totalRestSeconds = totalRestSeconds
        self.isComplete = isComplete
        self.setLogs = setLogs
        self.notes = notes
    }

    /// Sets logged for a given exercise, ordered by set index.
    public func logs(for exerciseID: UUID) -> [SetLog] {
        setLogs.filter { $0.exerciseID == exerciseID }.sorted { $0.setIndex < $1.setIndex }
    }
}
