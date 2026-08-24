import Foundation

/// Messages exchanged between the phone and the Watch.
///
/// Deliberately small: the Watch does not need the whole plan, only enough to
/// run the session in front of it. Keeping these as plain `Codable` values
/// means both sides share one definition and the wire format is testable
/// without a paired device.
public enum WatchSync {

    /// Sent phone -> Watch when a session starts, or when the Watch asks what
    /// it should be showing.
    public struct SessionSnapshot: Codable, Equatable, Sendable {
        public var sessionID: UUID
        public var workoutName: String
        public var bodyMapKey: BodyMapKey
        public var exercises: [ExerciseSnapshot]
        /// Index into `exercises` and the set within it, so a Watch joining
        /// mid-session lands in the right place.
        public var exerciseIndex: Int
        public var setIndex: Int

        public init(
            sessionID: UUID,
            workoutName: String,
            bodyMapKey: BodyMapKey,
            exercises: [ExerciseSnapshot],
            exerciseIndex: Int = 0,
            setIndex: Int = 0
        ) {
            self.sessionID = sessionID
            self.workoutName = workoutName
            self.bodyMapKey = bodyMapKey
            self.exercises = exercises
            self.exerciseIndex = exerciseIndex
            self.setIndex = setIndex
        }
    }

    /// One exercise, flattened for the Watch. Regions are carried so the Watch
    /// can pick its own artwork without another round trip.
    public struct ExerciseSnapshot: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var targetSets: Int
        public var targetReps: Int
        public var restSeconds: Int
        public var regions: Set<MuscleRegion>
        public var suggestedWeightKg: Double?

        public init(
            id: UUID,
            name: String,
            targetSets: Int,
            targetReps: Int,
            restSeconds: Int,
            regions: Set<MuscleRegion>,
            suggestedWeightKg: Double? = nil
        ) {
            self.id = id
            self.name = name
            self.targetSets = targetSets
            self.targetReps = targetReps
            self.restSeconds = restSeconds
            self.regions = regions
            self.suggestedWeightKg = suggestedWeightKg
        }
    }

    /// Sent Watch -> phone as sets are completed.
    ///
    /// Each carries its own `setIndex` so the phone can discard a duplicate
    /// that arrives twice after a reachability blip, rather than logging the
    /// same set again.
    public struct SetCompleted: Codable, Equatable, Sendable {
        public var sessionID: UUID
        public var exerciseID: UUID
        public var setIndex: Int
        public var reps: Int
        public var weightKg: Double?
        public var completedAt: Date

        public init(
            sessionID: UUID,
            exerciseID: UUID,
            setIndex: Int,
            reps: Int,
            weightKg: Double?,
            completedAt: Date = Date()
        ) {
            self.sessionID = sessionID
            self.exerciseID = exerciseID
            self.setIndex = setIndex
            self.reps = reps
            self.weightKg = weightKg
            self.completedAt = completedAt
        }
    }

    /// Sent Watch -> phone when the session ends, complete or not.
    public struct SessionEnded: Codable, Equatable, Sendable {
        public var sessionID: UUID
        public var completedAllSets: Bool
        /// Everything logged on the Watch, replayed in full so a session run
        /// entirely offline still lands on the phone.
        public var setLogs: [SetCompleted]
        public var endedAt: Date

        public init(
            sessionID: UUID,
            completedAllSets: Bool,
            setLogs: [SetCompleted],
            endedAt: Date = Date()
        ) {
            self.sessionID = sessionID
            self.completedAllSets = completedAllSets
            self.setLogs = setLogs
            self.endedAt = endedAt
        }
    }

    /// The whole upcoming plan, pushed to the Watch so it can start a workout
    /// with the phone out of reach. Small enough to sit in applicationContext.
    public struct PlanSnapshot: Codable, Equatable, Sendable {
        public var workouts: [UpcomingWorkout]
        public var repCountingEnabled: Bool

        public init(workouts: [UpcomingWorkout], repCountingEnabled: Bool = false) {
            self.workouts = workouts
            self.repCountingEnabled = repCountingEnabled
        }
    }

    public struct UpcomingWorkout: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var scheduledDate: Date
        public var snapshot: SessionSnapshot

        public init(id: UUID, scheduledDate: Date, snapshot: SessionSnapshot) {
            self.id = id
            self.scheduledDate = scheduledDate
            self.snapshot = snapshot
        }
    }

    /// The envelope actually put on the wire. A single type keeps the
    /// `WCSession` delegate to one decode path.
    public enum Message: Codable, Equatable, Sendable {
        case startSession(SessionSnapshot)
        case setCompleted(SetCompleted)
        case sessionEnded(SessionEnded)
        /// Watch asking the phone what, if anything, is in progress.
        case requestSnapshot
        /// Phone replying that nothing is active.
        case noActiveSession
        /// Phone pushing the upcoming plan so the Watch can work alone.
        case planUpdated(PlanSnapshot)
        /// Watch telling the phone it started one of those workouts itself.
        case watchStartedSession(sessionID: UUID, workoutID: UUID)
    }

    // MARK: - Wire format

    public static func encode(_ message: Message) throws -> Data {
        try JSONEncoder().encode(message)
    }

    public static func decode(_ data: Data) throws -> Message {
        try JSONDecoder().decode(Message.self, from: data)
    }

    /// `WCSession` deals in `[String: Any]`, so the encoded payload is carried
    /// under one key rather than trying to flatten the enum into a dictionary.
    public static let payloadKey = "gymkit.payload"

    public static func dictionary(for message: Message) throws -> [String: Any] {
        [payloadKey: try encode(message)]
    }

    public static func message(from dictionary: [String: Any]) throws -> Message {
        guard let data = dictionary[payloadKey] as? Data else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "missing \(payloadKey)")
            )
        }
        return try decode(data)
    }
}

public extension WatchSync.SessionSnapshot {
    /// Builds the Watch's view of a workout from the phone's model.
    init(
        sessionID: UUID,
        workout: ScheduledWorkout,
        suggestions: [UUID: Double] = [:]
    ) {
        self.init(
            sessionID: sessionID,
            workoutName: workout.trainingDay.name,
            bodyMapKey: workout.trainingDay.bodyMapKey,
            exercises: workout.trainingDay.plannedExercises.map { planned in
                WatchSync.ExerciseSnapshot(
                    id: planned.exercise.id,
                    name: planned.exercise.name,
                    targetSets: planned.targetSets,
                    targetReps: planned.targetReps,
                    restSeconds: planned.restSeconds,
                    regions: planned.exercise.regions,
                    suggestedWeightKg: suggestions[planned.exercise.id]
                )
            }
        )
    }
}
