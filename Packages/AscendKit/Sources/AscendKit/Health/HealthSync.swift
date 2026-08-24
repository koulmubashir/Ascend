import Foundation

/// A workout Health knows about that this app did not record.
public struct ImportedWorkout: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    /// HealthKit's own identifier, so the same workout is never imported twice.
    public var healthKitID: UUID
    public var activityName: String
    public var startedAt: Date
    public var duration: TimeInterval
    public var sourceName: String
    public var energyKilocalories: Double?

    public init(
        id: UUID = UUID(),
        healthKitID: UUID,
        activityName: String,
        startedAt: Date,
        duration: TimeInterval,
        sourceName: String,
        energyKilocalories: Double? = nil
    ) {
        self.id = id
        self.healthKitID = healthKitID
        self.activityName = activityName
        self.startedAt = startedAt
        self.duration = duration
        self.sourceName = sourceName
        self.energyKilocalories = energyKilocalories
    }
}

/// Merging data that arrives from Health.
///
/// The whole risk here is double counting. This app writes its own workouts to
/// Health, so reading workouts back naively would import them again and show
/// every session twice. Everything below exists to make that impossible.
public enum HealthSync {

    /// Keeps only workouts this app did not write, and that have not already
    /// been imported.
    ///
    /// Filtering by source bundle identifier is the reliable check - a workout
    /// written by Ascend carries Ascend as its source, whatever it is called.
    public static func newImports(
        from candidates: [ImportedWorkout],
        ourBundleIdentifier: String,
        alreadyImported: [ImportedWorkout],
        ownSessions: [WorkoutSession]
    ) -> [ImportedWorkout] {
        let seen = Set(alreadyImported.map(\.healthKitID))

        return candidates.filter { candidate in
            guard candidate.sourceName != ourBundleIdentifier else { return false }
            guard !seen.contains(candidate.healthKitID) else { return false }
            // Belt and braces: a workout overlapping one of our own sessions is
            // almost certainly the same session seen from the other side, even
            // if the source name did not match.
            return !overlapsOwnSession(candidate, ownSessions: ownSessions)
        }
    }

    /// True when the candidate starts within a couple of minutes of one of our
    /// own sessions. Clock skew between devices makes exact matching useless.
    private static func overlapsOwnSession(
        _ candidate: ImportedWorkout,
        ownSessions: [WorkoutSession]
    ) -> Bool {
        let tolerance: TimeInterval = 120
        return ownSessions.contains { session in
            abs(session.startedAt.timeIntervalSince(candidate.startedAt)) < tolerance
        }
    }

    /// One combined, date-ordered history of what you did, wherever it was
    /// recorded. Newest first, which is how history is read.
    public static func combinedHistory(
        ownSessions: [WorkoutSession],
        imported: [ImportedWorkout]
    ) -> [HistoryEntry] {
        let mine = ownSessions.map {
            HistoryEntry(
                date: $0.startedAt,
                title: "Workout",
                detail: nil,
                isFromThisApp: true,
                sessionID: $0.id
            )
        }
        let theirs = imported.map {
            HistoryEntry(
                date: $0.startedAt,
                title: $0.activityName,
                detail: $0.sourceName,
                isFromThisApp: false,
                sessionID: nil
            )
        }
        return (mine + theirs).sorted { $0.date > $1.date }
    }

    public struct HistoryEntry: Identifiable, Hashable, Sendable {
        public var date: Date
        public var title: String
        /// Which app recorded it, shown only for workouts from elsewhere.
        public var detail: String?
        public var isFromThisApp: Bool
        public var sessionID: UUID?

        public var id: String { "\(date.timeIntervalSince1970)-\(title)" }
    }

    /// Whether a measurement read from Health is worth storing, given what is
    /// already known.
    ///
    /// Health can hand back years of daily weigh-ins. Only a reading that is
    /// newer than the latest one held is useful.
    public static func shouldImport(
        _ measurement: BodyMeasurement,
        existing: [BodyMeasurement]
    ) -> Bool {
        guard MeasurementTracker.isPlausible(measurement.value, for: measurement.kind) else {
            return false
        }
        guard let latest = MeasurementTracker.latest(measurement.kind, in: existing) else {
            return true
        }
        return measurement.recordedAt > latest.recordedAt
    }
}
