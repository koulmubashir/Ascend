import Foundation

/// Reads set history to spot personal records and suggest the next target.
///
/// Everything here is derived from `SetLog`s that Phase 1 already records, so
/// there is no extra tracking to build.
public enum ProgressiveOverloadEngine {

    public enum Metric: String, Codable, Sendable {
        case maxWeight, maxReps, estimatedOneRepMax
    }

    public struct PersonalRecord: Equatable, Codable, Hashable, Sendable {
        public var exerciseID: UUID
        public var metric: Metric
        public var value: Double
        public var achievedAt: Date

        public init(exerciseID: UUID, metric: Metric, value: Double, achievedAt: Date) {
            self.exerciseID = exerciseID
            self.metric = metric
            self.value = value
            self.achievedAt = achievedAt
        }
    }

    public struct Suggestion: Equatable, Sendable {
        public var exerciseID: UUID
        public var weight: Double?
        public var reps: Int
        public var rationale: Rationale

        public enum Rationale: String, Equatable, Sendable {
            /// Hit every target rep last time - time to add load.
            case addWeight
            /// Cleared the set but short of target reps - repeat and build reps.
            case addReps
            /// Fell well short - hold the same target.
            case holdSteady
            /// Never done this one before.
            case noHistory
        }
    }

    /// Epley formula. Reps are clamped because the estimate degrades badly past ~12.
    public static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return 0 }
        let capped = min(reps, 12)
        return weight * (1.0 + Double(capped) / 30.0)
    }

    /// Records beaten by `logs`, given what was already on file.
    public static func newRecords(
        from logs: [SetLog],
        existing: [PersonalRecord]
    ) -> [PersonalRecord] {

        var best: [String: PersonalRecord] = [:]
        for record in existing {
            best["\(record.exerciseID)-\(record.metric.rawValue)"] = record
        }

        var found: [String: PersonalRecord] = [:]

        for log in logs {
            var candidates: [(Metric, Double)] = [(.maxReps, Double(log.reps))]
            if let weight = log.weightKg, weight > 0 {
                candidates.append((.maxWeight, weight))
                candidates.append((.estimatedOneRepMax, estimatedOneRepMax(weight: weight, reps: log.reps)))
            }

            for (metric, value) in candidates {
                let key = "\(log.exerciseID)-\(metric.rawValue)"
                let toBeat = max(best[key]?.value ?? 0, found[key]?.value ?? 0)
                guard value > toBeat else { continue }
                found[key] = PersonalRecord(
                    exerciseID: log.exerciseID,
                    metric: metric,
                    value: value,
                    achievedAt: log.completedAt
                )
            }
        }

        return found.values.sorted { $0.exerciseID.uuidString < $1.exerciseID.uuidString }
    }

    /// What to aim for next time on `exercise`.
    ///
    /// - Parameters:
    ///   - history: every set ever logged for this exercise, any order
    ///   - increment: smallest weight step available, e.g. 2.5kg
    public static func suggestion(
        for exercise: Exercise,
        history: [SetLog],
        increment: Double = 2.5
    ) -> Suggestion {

        let mine = history
            .filter { $0.exerciseID == exercise.id }
            .sorted { $0.completedAt < $1.completedAt }

        guard let mostRecent = mine.last else {
            return Suggestion(
                exerciseID: exercise.id,
                weight: nil,
                reps: exercise.defaultReps,
                rationale: .noHistory
            )
        }

        // All sets from the most recent session for this exercise.
        let cal = Calendar.current
        let lastDay = cal.startOfDay(for: mostRecent.completedAt)
        let lastSession = mine.filter { cal.startOfDay(for: $0.completedAt) == lastDay }

        let target = exercise.defaultReps
        let topWeight = lastSession.compactMap(\.weightKg).max()
        let hitAllReps = lastSession.count >= exercise.defaultSets
            && lastSession.allSatisfy { $0.reps >= target }

        if hitAllReps, let weight = topWeight, weight > 0 {
            return Suggestion(
                exerciseID: exercise.id,
                weight: weight + increment,
                reps: target,
                rationale: .addWeight
            )
        }

        let bestReps = lastSession.map(\.reps).max() ?? 0
        if bestReps >= max(1, target - 2) {
            return Suggestion(
                exerciseID: exercise.id,
                weight: topWeight,
                reps: target,
                rationale: .addReps
            )
        }

        return Suggestion(
            exerciseID: exercise.id,
            weight: topWeight,
            reps: target,
            rationale: .holdSteady
        )
    }
}
