import Foundation

/// Trend calculations over logged sets.
///
/// All of this reads `SetLog` history that the app already stores - no new
/// tracking, just arithmetic over what is there.
public enum ProgressStats {

    /// Weight moved in a set: weight times reps. Bodyweight work has no weight,
    /// so it contributes zero volume rather than being silently counted as one.
    public static func volume(of log: SetLog) -> Double {
        (log.weightKg ?? 0) * Double(log.reps)
    }

    public static func totalVolume(_ logs: [SetLog]) -> Double {
        logs.reduce(0) { $0 + volume(of: $1) }
    }

    /// One point per session for a single exercise, oldest first.
    ///
    /// Sets are grouped by calendar day rather than by session id, so two
    /// sessions on the same day - a missed workout finished later, say - read
    /// as one point on the chart instead of two.
    public static func history(
        for exerciseID: UUID,
        in logs: [SetLog],
        calendar: Calendar = .current
    ) -> [SessionPoint] {
        let mine = logs.filter { $0.exerciseID == exerciseID }
        guard !mine.isEmpty else { return [] }

        let byDay = Dictionary(grouping: mine) { calendar.startOfDay(for: $0.completedAt) }
        return byDay
            .map { day, logs in
                SessionPoint(
                    date: day,
                    topSetWeight: logs.compactMap(\.weightKg).max(),
                    topSetReps: logs.map(\.reps).max() ?? 0,
                    totalVolume: totalVolume(logs),
                    setCount: logs.count,
                    estimatedOneRepMax: logs.compactMap { log -> Double? in
                        guard let weight = log.weightKg, weight > 0 else { return nil }
                        return ProgressiveOverloadEngine.estimatedOneRepMax(weight: weight, reps: log.reps)
                    }.max()
                )
            }
            .sorted { $0.date < $1.date }
    }

    public struct SessionPoint: Identifiable, Hashable, Sendable {
        public var date: Date
        public var topSetWeight: Double?
        public var topSetReps: Int
        public var totalVolume: Double
        public var setCount: Int
        public var estimatedOneRepMax: Double?

        public var id: Date { date }
    }

    /// Volume per muscle region across a date range, for spotting a group you
    /// have quietly stopped training.
    public static func volumeByRegion(
        logs: [SetLog],
        library: ExerciseLibrary,
        from start: Date,
        to end: Date
    ) -> [MuscleRegion: Double] {
        var totals: [MuscleRegion: Double] = [:]
        for log in logs where log.completedAt >= start && log.completedAt <= end {
            guard let exercise = library.exercise(id: log.exerciseID) else { continue }
            let share = volume(of: log)
            // Volume is attributed in full to every region the exercise trains
            // rather than split between them: a bench press genuinely loads the
            // chest and the triceps, and dividing by three would understate both.
            for region in exercise.regions {
                totals[region, default: 0] += share
            }
        }
        return totals
    }

    /// Daily training volume, oldest first, with untrained days present as zero
    /// so a chart shows the gaps.
    public static func dailyVolume(
        _ logs: [SetLog],
        endingOn date: Date,
        days: Int,
        calendar: Calendar = .current
    ) -> [(date: Date, volume: Double)] {
        guard days > 0 else { return [] }
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            let start = calendar.startOfDay(for: day)
            let matching = logs.filter { calendar.isDate($0.completedAt, inSameDayAs: day) }
            return (start, totalVolume(matching))
        }
    }

    /// Change between the first and last session, as a percentage.
    ///
    /// Nil when there is nothing meaningful to compare - fewer than two
    /// sessions, or no weight recorded.
    public static func trend(_ points: [SessionPoint]) -> Double? {
        let weights = points.compactMap(\.topSetWeight)
        guard weights.count >= 2, let first = weights.first, first > 0, let last = weights.last
        else { return nil }
        return (last - first) / first * 100
    }
}
