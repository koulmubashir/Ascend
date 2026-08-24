import Foundation
import AscendKit

/// Body measurements, deload scheduling, and session notes.
extension AppStore {

    // MARK: - Measurements

    @discardableResult
    func logMeasurement(kind: MeasurementKind, value: Double) -> Bool {
        // Reject a slipped decimal point rather than silently storing 7.5 kg.
        guard MeasurementTracker.isPlausible(value, for: kind) else { return false }
        measurements.append(BodyMeasurement(kind: kind, value: value))
        save()
        return true
    }

    func removeMeasurement(_ measurement: BodyMeasurement) {
        measurements.removeAll { $0.id == measurement.id }
        save()
    }

    func latestMeasurement(_ kind: MeasurementKind) -> BodyMeasurement? {
        MeasurementTracker.latest(kind, in: measurements)
    }

    func measurementSeries(_ kind: MeasurementKind) -> [BodyMeasurement] {
        MeasurementTracker.series(kind, in: measurements)
    }

    func measurementChange(_ kind: MeasurementKind, days: Int = 90) -> Double? {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return MeasurementTracker.change(kind, in: measurements, since: since)
    }

    var trackedMeasurements: [MeasurementKind] {
        MeasurementTracker.tracked(in: measurements)
    }

    // MARK: - Deload

    var isDeloadWeek: Bool {
        guard let start = plan?.createdAt else { return false }
        return PeriodizationEngine.isDeloadWeek(
            Date(), planStart: start, settings: settings.periodization
        )
    }

    var weeksUntilDeload: Int? {
        guard let start = plan?.createdAt else { return nil }
        return PeriodizationEngine.weeksUntilDeload(
            from: Date(), planStart: start, settings: settings.periodization
        )
    }

    /// Targets for an exercise today, with the deload applied if this is one.
    func adjustedTargets(for planned: PlannedExercise) -> PeriodizationEngine.Adjustment {
        guard let start = plan?.createdAt else {
            return PeriodizationEngine.Adjustment(
                sets: planned.targetSets, reps: planned.targetReps,
                weight: suggestion(for: planned.exercise).weight, isDeload: false
            )
        }
        return PeriodizationEngine.adjust(
            planned,
            on: Date(),
            planStart: start,
            settings: settings.periodization,
            suggestedWeight: suggestion(for: planned.exercise).weight
        )
    }

    // MARK: - Session notes

    func setNotes(_ text: String, on sessionID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].notes = trimmed.isEmpty ? nil : trimmed
            save()
        } else if activeSession?.id == sessionID {
            activeSession?.notes = trimmed.isEmpty ? nil : trimmed
        }
    }
}
