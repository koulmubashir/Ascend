import Foundation
import AscendKit

/// Plan editing, custom exercises, and backup.
///
/// Split out of `AppStore` to keep that file about session lifecycle. Every
/// mutation here goes through `save()`, which also refreshes notifications and
/// the widget snapshot.
extension AppStore {

    // MARK: - Custom exercises

    /// Exercises the user added, on top of the seeded library.
    var allExercises: [Exercise] {
        (library.all + customExercises).sorted { $0.name < $1.name }
    }

    /// Only what the user's equipment allows. Custom exercises are always
    /// included - if you added it yourself, you can evidently do it.
    var availableExercises: [Exercise] {
        let usable = library.all.filter {
            PlanRecommender.isAvailable($0, with: settings.equipment)
        }
        return (usable + customExercises).sorted { $0.name < $1.name }
    }

    func exercise(id: UUID) -> Exercise? {
        library.exercise(id: id) ?? customExercises.first { $0.id == id }
    }

    func addCustomExercise(
        name: String,
        group: MuscleGroup,
        regions: Set<MuscleRegion>,
        sets: Int,
        reps: Int,
        rest: Int
    ) -> Exercise? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let exercise = Exercise(
            name: trimmed,
            group: group,
            regions: regions.isEmpty ? group.regions : regions,
            defaultSets: max(1, sets),
            defaultReps: max(1, reps),
            defaultRestSeconds: max(0, rest)
        )
        customExercises.append(exercise)
        save()
        return exercise
    }

    func deleteCustomExercise(_ exercise: Exercise) {
        customExercises.removeAll { $0.id == exercise.id }
        // Anything already planned keeps working - the exercise is embedded in
        // the PlannedExercise, not referenced by id - so removing it only stops
        // it being picked again.
        save()
    }

    // MARK: - Plan editing

    /// Applies an edit through `PlanEditor` so it reaches the plan template and
    /// every future instance, not just the one scheduled day the user opened.
    private func withTrainingDay(
        _ workoutID: UUID,
        _ body: (inout TrainingDay) -> Void
    ) {
        guard let index = schedule.firstIndex(where: { $0.id == workoutID }) else { return }
        var day = schedule[index].trainingDay
        body(&day)

        let outcome = PlanEditor.apply(
            day,
            plan: plan,
            schedule: schedule,
            editing: workoutID,
            scope: editScope
        )
        plan = outcome.plan
        schedule = outcome.schedule
        lastEditAffectedFutureDays = outcome.updatedInstances
        saveAndSync()
    }

    func renameDay(_ workout: ScheduledWorkout, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withTrainingDay(workout.id) { $0.name = trimmed }
    }

    func addExercise(_ exercise: Exercise, to workout: ScheduledWorkout) {
        withTrainingDay(workout.id) { day in
            let nextOrder = (day.plannedExercises.map(\.orderIndex).max() ?? -1) + 1
            day.plannedExercises.append(PlannedExercise(exercise: exercise, orderIndex: nextOrder))
        }
    }

    func removeExercise(_ planned: PlannedExercise, from workout: ScheduledWorkout) {
        withTrainingDay(workout.id) { day in
            day.plannedExercises.removeAll { $0.id == planned.id }
            reindex(&day)
        }
    }

    /// Joins an exercise to the one above it, or separates it again.
    ///
    /// Supersets are always a contiguous run, so pairing works on neighbours
    /// rather than letting any two exercises be linked from anywhere in the
    /// list - that keeps the engine's traversal and this list in agreement.
    func toggleSuperset(_ planned: PlannedExercise, in workout: ScheduledWorkout) {
        withTrainingDay(workout.id) { day in
            day.plannedExercises = PlanEditor.toggleSuperset(planned.id, in: day.plannedExercises)
        }
    }

    func moveExercises(in workout: ScheduledWorkout, from offsets: IndexSet, to destination: Int) {
        withTrainingDay(workout.id) { day in
            day.plannedExercises.sort { $0.orderIndex < $1.orderIndex }
            day.plannedExercises.move(fromOffsets: offsets, toOffset: destination)
            reindex(&day)
        }
    }

    func updateTargets(
        _ planned: PlannedExercise,
        in workout: ScheduledWorkout,
        sets: Int? = nil,
        reps: Int? = nil,
        rest: Int? = nil
    ) {
        withTrainingDay(workout.id) { day in
            guard let index = day.plannedExercises.firstIndex(where: { $0.id == planned.id })
            else { return }
            if let sets { day.plannedExercises[index].targetSets = max(1, sets) }
            if let reps { day.plannedExercises[index].targetReps = max(1, reps) }
            if let rest { day.plannedExercises[index].restSeconds = max(0, rest) }
        }
    }

    /// Order indices must stay contiguous - the session engine sorts by them
    /// and gaps would still work but make reordering confusing to debug.
    private func reindex(_ day: inout TrainingDay) {
        day.plannedExercises = day.plannedExercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .enumerated()
            .map { index, planned in
                var copy = planned
                copy.orderIndex = index
                return copy
            }
    }

    // MARK: - Progress

    func history(for exercise: Exercise) -> [ProgressStats.SessionPoint] {
        ProgressStats.history(for: exercise.id, in: allSetLogs)
    }

    func trend(for exercise: Exercise) -> Double? {
        ProgressStats.trend(history(for: exercise))
    }

    func dailyVolume(days: Int = 30) -> [(date: Date, volume: Double)] {
        ProgressStats.dailyVolume(allSetLogs, endingOn: Date(), days: days)
    }

    /// Volume per region over the last `days`, for spotting a neglected group.
    func volumeByRegion(days: Int = 28) -> [MuscleRegion: Double] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let combined = ExerciseLibrary(all: library.all + customExercises)
        return ProgressStats.volumeByRegion(
            logs: allSetLogs, library: combined, from: start, to: Date()
        )
    }

    // MARK: - Backup

    /// Everything, as JSON. Enough to restore onto a new phone.
    func exportData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(makeSnapshot())
    }

    var exportFilename: String {
        "gymtracker-\(Date().formatted(.iso8601.year().month().day())).json"
    }

    enum ImportResult: Equatable {
        case success(sessions: Int)
        case failed(String)
    }

    // MARK: - iCloud

    /// Pushes the current store to iCloud. A backup, not live sync - see
    /// `CloudBackup` for why that distinction is deliberate.
    @discardableResult
    func backUpToCloud() -> CloudBackup.Result {
        guard let data = exportData() else { return .failed("Could not encode your data.") }
        return cloud.upload(data)
    }

    /// Restores the most recent iCloud backup, replacing everything locally.
    @discardableResult
    func restoreFromCloud() -> ImportResult {
        guard let data = cloud.download() else {
            return .failed("No iCloud backup found.")
        }
        return importData(data)
    }

    /// Replaces everything with the contents of a backup.
    ///
    /// Deliberately destructive rather than merging: two histories with
    /// overlapping session ids would be ambiguous to reconcile, and a restore
    /// is normally onto an empty install.
    @discardableResult
    func importData(_ data: Data) -> ImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else {
            return .failed("That file is not a Ascend backup.")
        }
        apply(snapshot)
        save()
        return .success(sessions: snapshot.sessions.count)
    }
}
