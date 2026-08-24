import Foundation

/// A vitals reading tied to a session.
///
/// `source` exists so the UI can be honest about where a number came from.
/// Heart rate during a workout is genuinely live; blood oxygen is a spot check
/// the system took at some point; wrist temperature is measured overnight. All
/// three are "vitals", but presenting them the same way would be misleading.
public struct VitalsSample: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var sessionID: UUID?
    public var kind: VitalsKind
    public var value: Double
    public var recordedAt: Date
    /// How this reading was obtained. Same vocabulary as `VitalsKind`'s
    /// declared availability, recorded per sample so a value's provenance
    /// survives even if the enum's defaults change later.
    public var source: VitalsAvailability

    public init(
        id: UUID = UUID(),
        sessionID: UUID? = nil,
        kind: VitalsKind,
        value: Double,
        recordedAt: Date = Date(),
        source: VitalsAvailability
    ) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.value = value
        self.recordedAt = recordedAt
        self.source = source
    }
}

public enum VitalsKind: String, Codable, CaseIterable, Sendable {
    case heartRate
    case bloodOxygen
    case wristTemperature

    public var displayName: String {
        switch self {
        case .heartRate:        return "Heart rate"
        case .bloodOxygen:      return "Blood oxygen"
        case .wristTemperature: return "Wrist temperature"
        }
    }

    public var unit: String {
        switch self {
        case .heartRate:        return "bpm"
        case .bloodOxygen:      return "%"
        case .wristTemperature: return "°C"
        }
    }

    /// How this reading is actually obtained. Drives the caveat the UI shows.
    public var availability: VitalsAvailability {
        switch self {
        case .heartRate:        return .liveDuringWorkout
        case .bloodOxygen:      return .periodicSpotCheck
        case .wristTemperature: return .overnightOnly
        }
    }

    /// Minimum Watch generation. Used only for the explanatory text - the app
    /// decides what to show from whether data actually arrives, not from a
    /// hardcoded device check.
    public var requiresWatch: String {
        switch self {
        case .heartRate:        return "Series 4 or later"
        case .bloodOxygen:      return "Series 6 or later"
        case .wristTemperature: return "Series 8 or Ultra"
        }
    }
}

public enum VitalsAvailability: String, Codable, Sendable {
    /// Streams continuously while a workout session is running.
    case liveDuringWorkout
    /// The system takes readings periodically, and generally not during a
    /// workout. The app can only show the most recent one.
    case periodicSpotCheck
    /// Written once per night during sleep. Never available mid-workout.
    case overnightOnly

    public var caveat: String {
        switch self {
        case .liveDuringWorkout:
            return "Recorded continuously while you train."
        case .periodicSpotCheck:
            return "A spot check taken periodically, usually not during a workout."
        case .overnightOnly:
            return "Measured overnight while you sleep, not during a workout."
        }
    }
}

public enum VitalsSummary {

    /// Live heart-rate figures for a session.
    public static func heartRate(
        for sessionID: UUID,
        in samples: [VitalsSample]
    ) -> (average: Int, peak: Int)? {
        let beats = samples
            .filter { $0.sessionID == sessionID && $0.kind == .heartRate }
            .map(\.value)
        guard !beats.isEmpty else { return nil }
        let average = beats.reduce(0, +) / Double(beats.count)
        return (Int(average.rounded()), Int(beats.max() ?? 0))
    }

    /// Most recent reading of a kind, whatever its age.
    public static func latest(_ kind: VitalsKind, in samples: [VitalsSample]) -> VitalsSample? {
        samples.filter { $0.kind == kind }.max { $0.recordedAt < $1.recordedAt }
    }

    /// Average heart rate across sessions in a date range, for the weekly view.
    public static func averageHeartRate(
        in samples: [VitalsSample],
        from start: Date,
        to end: Date
    ) -> Int? {
        let beats = samples
            .filter { $0.kind == .heartRate && $0.recordedAt >= start && $0.recordedAt <= end }
            .map(\.value)
        guard !beats.isEmpty else { return nil }
        return Int((beats.reduce(0, +) / Double(beats.count)).rounded())
    }

    /// Which kinds have ever produced data.
    ///
    /// This is how the app decides what to show. There is no reliable public
    /// API for "which Watch is paired", so capability is inferred from readings
    /// actually arriving rather than guessed from a model number.
    public static func availableKinds(in samples: [VitalsSample]) -> Set<VitalsKind> {
        Set(samples.map(\.kind))
    }
}
