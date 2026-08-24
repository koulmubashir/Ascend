import Foundation

/// Something you measure about yourself, rather than about a workout.
public enum MeasurementKind: String, Codable, CaseIterable, Sendable {
    case bodyWeight
    case waist
    case chest
    case arm
    case thigh
    case bodyFat

    public var displayName: String {
        switch self {
        case .bodyWeight: return "Body weight"
        case .waist:      return "Waist"
        case .chest:      return "Chest"
        case .arm:        return "Arm"
        case .thigh:      return "Thigh"
        case .bodyFat:    return "Body fat"
        }
    }

    public var unit: String {
        switch self {
        case .bodyWeight: return "kg"
        case .bodyFat:    return "%"
        default:          return "cm"
        }
    }

    /// Sensible bounds, used to reject a slipped decimal point rather than to
    /// judge anybody's body.
    public var plausibleRange: ClosedRange<Double> {
        switch self {
        case .bodyWeight: return 25...300
        case .bodyFat:    return 1...70
        case .waist:      return 40...200
        case .chest:      return 50...200
        case .arm:        return 15...80
        case .thigh:      return 25...110
        }
    }

    /// Whether going down is the usual goal. Only used to colour a trend, and
    /// deliberately not applied to body weight - people are cutting or bulking
    /// and the app has no business assuming which.
    public var lowerIsTypicallyBetter: Bool {
        self == .bodyFat || self == .waist
    }
}

public struct BodyMeasurement: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var kind: MeasurementKind
    public var value: Double
    public var recordedAt: Date

    public init(id: UUID = UUID(), kind: MeasurementKind, value: Double, recordedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.value = value
        self.recordedAt = recordedAt
    }
}

public enum MeasurementTracker {

    /// Rejects values outside the plausible range, which in practice means a
    /// misplaced decimal point - 7.5 kg or 750 kg rather than 75.
    public static func isPlausible(_ value: Double, for kind: MeasurementKind) -> Bool {
        kind.plausibleRange.contains(value)
    }

    public static func latest(_ kind: MeasurementKind, in all: [BodyMeasurement]) -> BodyMeasurement? {
        all.filter { $0.kind == kind }.max { $0.recordedAt < $1.recordedAt }
    }

    public static func series(
        _ kind: MeasurementKind,
        in all: [BodyMeasurement]
    ) -> [BodyMeasurement] {
        all.filter { $0.kind == kind }.sorted { $0.recordedAt < $1.recordedAt }
    }

    /// Absolute change over the window, or nil when there is nothing to compare.
    public static func change(
        _ kind: MeasurementKind,
        in all: [BodyMeasurement],
        since: Date
    ) -> Double? {
        let points = series(kind, in: all).filter { $0.recordedAt >= since }
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        return last.value - first.value
    }

    /// Kinds that have at least one reading, so the UI shows what you actually
    /// track rather than six empty cards.
    public static func tracked(in all: [BodyMeasurement]) -> [MeasurementKind] {
        MeasurementKind.allCases.filter { kind in all.contains { $0.kind == kind } }
    }
}
