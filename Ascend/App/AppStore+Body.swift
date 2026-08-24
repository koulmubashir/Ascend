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

    // MARK: - Health import

    /// Pulls in what Health knows that this app does not: workouts logged
    /// elsewhere, weigh-ins from a scale, dietary entries from another app.
    ///
    /// Safe to call repeatedly - `HealthSync` rejects anything already held or
    /// written by this app, so nothing is double counted.
    func importFromHealth() async {
        guard settings.healthKitEnabled, health.isAuthorised else { return }

        let since = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let candidates = await health.importableWorkouts(since: since)
        let fresh = HealthSync.newImports(
            from: candidates,
            ourBundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            alreadyImported: importedWorkouts,
            ownSessions: sessions
        )
        if !fresh.isEmpty { importedWorkouts.append(contentsOf: fresh) }

        for measurement in await health.importableMeasurements()
        where HealthSync.shouldImport(measurement, existing: measurements) {
            measurements.append(measurement)
        }

        await refreshExternalIntake()

        if !fresh.isEmpty { save() }
    }

    /// Today's intake including anything logged in other apps, so the totals
    /// are not misleadingly low.
    ///
    /// Takes the larger of the two rather than the sum. When mirroring to
    /// Health is on, Health already contains our own entries and adding would
    /// double count; when it is off, Health only knows what other apps logged
    /// and can be lower than ours. The larger figure is right either way.
    func displayTotal(for kind: IntakeKind) -> Double {
        max(todayTotal(for: kind), externalIntake[kind] ?? 0)
    }

    private func refreshExternalIntake() async {
        guard settings.healthKitEnabled, health.isAuthorised else {
            externalIntake = [:]
            return
        }
        for kind in IntakeKind.allCases {
            externalIntake[kind] = await health.dietaryTotalToday(kind)
        }
    }

    /// Asks Health to wake us when workouts change elsewhere. Idempotent, and
    /// harmless to call whenever authorisation state changes.
    func startHealthObservation() {
        guard settings.healthKitEnabled, health.isAuthorised, !isObservingHealth else { return }
        isObservingHealth = true
        health.enableBackgroundDelivery { [weak self] in
            Task { @MainActor in await self?.importFromHealth() }
        }
    }

    /// One list of everything, wherever it was recorded.
    var combinedHistory: [HealthSync.HistoryEntry] {
        HealthSync.combinedHistory(ownSessions: sessions, imported: importedWorkouts)
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
