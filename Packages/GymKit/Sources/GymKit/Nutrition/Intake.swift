import Foundation

/// What is being logged. Protein and water share a shape - an amount at a
/// moment - so they share a type rather than duplicating one per nutrient.
public enum IntakeKind: String, Codable, CaseIterable, Sendable {
    case protein
    case water

    public var displayName: String {
        switch self {
        case .protein: return "Protein"
        case .water:   return "Water"
        }
    }

    /// Unit the amount is stored in.
    public var unit: String {
        switch self {
        case .protein: return "g"
        case .water:   return "ml"
        }
    }

    public var defaultGoal: Double {
        switch self {
        case .protein: return 140
        case .water:   return 2500
        }
    }

    /// Quick-add buttons, so the common case is one tap.
    public var presets: [Double] {
        switch self {
        case .protein: return [20, 30, 40]
        case .water:   return [250, 500, 750]
        }
    }
}

public struct IntakeEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var kind: IntakeKind
    public var amount: Double
    public var loggedAt: Date

    public init(id: UUID = UUID(), kind: IntakeKind, amount: Double, loggedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.loggedAt = loggedAt
    }
}

public enum IntakeTracker {

    /// Total logged for a kind on a given day.
    public static func total(
        _ entries: [IntakeEntry],
        kind: IntakeKind,
        on date: Date,
        calendar: Calendar = .current
    ) -> Double {
        entries
            .filter { $0.kind == kind && calendar.isDate($0.loggedAt, inSameDayAs: date) }
            .reduce(0) { $0 + $1.amount }
    }

    /// Progress toward a goal, clamped to 0...1 so a bar cannot overflow.
    public static func progress(total: Double, goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return min(1, max(0, total / goal))
    }

    /// Totals for the last `days` days, oldest first, for a weekly chart.
    public static func dailyTotals(
        _ entries: [IntakeEntry],
        kind: IntakeKind,
        endingOn date: Date,
        days: Int,
        calendar: Calendar = .current
    ) -> [(date: Date, total: Double)] {
        guard days > 0 else { return [] }
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            return (calendar.startOfDay(for: day), total(entries, kind: kind, on: day, calendar: calendar))
        }
    }

    /// Times of day to remind, spread evenly between waking and sleeping.
    ///
    /// Deliberately neutral about behaviour: these prompt you to *log*, not to
    /// drink or eat on a schedule. The app tracks intake, it does not coach.
    public static func reminderTimes(
        wakeHour: Int = 8,
        sleepHour: Int = 22,
        count: Int = 4
    ) -> [DateComponents] {
        guard count > 0, sleepHour > wakeHour else { return [] }
        let span = sleepHour - wakeHour
        // Spread inside the waking window rather than firing the instant you
        // wake or as you go to bed.
        let step = Double(span) / Double(count + 1)
        return (1...count).map { index in
            let hour = Double(wakeHour) + step * Double(index)
            return DateComponents(hour: Int(hour), minute: Int((hour - hour.rounded(.down)) * 60))
        }
    }
}
