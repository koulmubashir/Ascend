import Foundation

/// Scheduled deload weeks.
///
/// The idea: after several weeks of pushing, back the volume off deliberately
/// rather than grinding until something hurts. This is a simple fixed-cycle
/// scheme - every Nth week is lighter - not autoregulation. It does not read
/// heart rate or sleep and does not pretend to know how recovered you are.
public enum PeriodizationEngine {

    public struct Settings: Codable, Hashable, Sendable {
        public var isEnabled: Bool
        /// Deload every `cycleWeeks` weeks; the last week of each cycle is the
        /// light one.
        public var cycleWeeks: Int
        /// Fraction of normal working weight on a deload week.
        public var intensityFactor: Double
        /// Fraction of normal sets on a deload week, rounded up so nothing
        /// drops to zero sets.
        public var volumeFactor: Double

        public init(
            isEnabled: Bool = false,
            cycleWeeks: Int = 4,
            intensityFactor: Double = 0.8,
            volumeFactor: Double = 0.6
        ) {
            self.isEnabled = isEnabled
            self.cycleWeeks = max(2, cycleWeeks)
            self.intensityFactor = min(1, max(0.3, intensityFactor))
            self.volumeFactor = min(1, max(0.3, volumeFactor))
        }
    }

    /// Zero-based week number since the plan was created.
    public static func weekIndex(
        for date: Date,
        planStart: Date,
        calendar: Calendar = .current
    ) -> Int {
        let start = calendar.startOfDay(for: planStart)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
        return max(0, days / 7)
    }

    /// True on the final week of each cycle - week 3 of a 4 week cycle.
    public static func isDeloadWeek(
        _ date: Date,
        planStart: Date,
        settings: Settings,
        calendar: Calendar = .current
    ) -> Bool {
        guard settings.isEnabled else { return false }
        let index = weekIndex(for: date, planStart: planStart, calendar: calendar)
        // Never deload the very first week - there is nothing to recover from.
        guard index > 0 else { return false }
        return (index + 1) % settings.cycleWeeks == 0
    }

    /// Targets for one exercise, adjusted if this is a deload week.
    public static func adjust(
        _ planned: PlannedExercise,
        on date: Date,
        planStart: Date,
        settings: Settings,
        suggestedWeight: Double?,
        calendar: Calendar = .current
    ) -> Adjustment {
        guard isDeloadWeek(date, planStart: planStart, settings: settings, calendar: calendar) else {
            return Adjustment(
                sets: planned.targetSets,
                reps: planned.targetReps,
                weight: suggestedWeight,
                isDeload: false
            )
        }

        // Round up so a 3 set exercise becomes 2, not 1.8 then 1.
        let sets = max(1, Int((Double(planned.targetSets) * settings.volumeFactor).rounded(.up)))
        let weight = suggestedWeight.map { raw -> Double in
            // Snap to something loadable, otherwise the number is unusable at
            // the bar.
            let target = raw * settings.intensityFactor
            return PlateCalculator.plates(for: target).achievedTotal
        }

        return Adjustment(sets: sets, reps: planned.targetReps, weight: weight, isDeload: true)
    }

    public struct Adjustment: Equatable, Sendable {
        public var sets: Int
        public var reps: Int
        public var weight: Double?
        public var isDeload: Bool

        public init(sets: Int, reps: Int, weight: Double?, isDeload: Bool) {
            self.sets = sets
            self.reps = reps
            self.weight = weight
            self.isDeload = isDeload
        }

        public var summary: String {
            isDeload ? "Deload week — lighter and fewer sets" : ""
        }
    }

    /// How many weeks until the next deload, for showing in the summary.
    public static func weeksUntilDeload(
        from date: Date,
        planStart: Date,
        settings: Settings,
        calendar: Calendar = .current
    ) -> Int? {
        guard settings.isEnabled else { return nil }
        let index = weekIndex(for: date, planStart: planStart, calendar: calendar)
        if isDeloadWeek(date, planStart: planStart, settings: settings, calendar: calendar) {
            return 0
        }
        let positionInCycle = (index + 1) % settings.cycleWeeks
        return settings.cycleWeeks - positionInCycle
    }
}
