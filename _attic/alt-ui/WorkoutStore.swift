import Foundation
import GymKit

/// App state, persisted as JSON in the App Group container.
///
/// Persistence sits behind this one type so it can be swapped for Core Data
/// later without touching any view code.
@MainActor
final class WorkoutStore: ObservableObject {

    @Published private(set) var state: AppState
    let library = ExerciseLibrary.starter

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.state = Self.load(from: self.fileURL) ?? AppState()
    }

    // MARK: - Derived

    var hasCompletedOnboarding: Bool { state.plan != nil }

    var todaysWorkout: ScheduledWorkout? {
        let cal = Calendar.current
        return state.schedule.first {
            cal.isDateInToday($0.scheduledDate) && $0.status == .upcoming
        }
    }

    var nextWorkout: ScheduledWorkout? {
        state.schedule
            .filter { $0.status == .upcoming }
            .sorted { $0.scheduledDate < $1.scheduledDate }
            .first
    }

    /// Consecutive days ending today that had a completed session.
    var streak: Int {
        let cal = Calendar.current
        let done = Set(state.schedule
            .filter { $0.status == .completed }
            .map { cal.startOfDay(for: $0.scheduledDate) })

        var count = 0
        var day = cal.startOfDay(for: Date())
        while done.contains(day) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    func exercise(id: UUID) -> Exercise? { library.exercise(id: id) }

    // MARK: - Mutations

    func createPlan(daysPerWeek: Int) {
        let days = PlanBuilder.trainingDays(forDaysPerWeek: daysPerWeek, library: library)
        state.plan = WorkoutPlan(daysPerWeek: daysPerWeek, trainingDays: days)
        state.schedule = PlanBuilder.schedule(days: days, startingAfter: Date())
        save()
    }

    func record(session: WorkoutSession, for workout: ScheduledWorkout) {
        state.sessions.append(session)

        if let index = state.schedule.firstIndex(where: { $0.id == workout.id }) {
            state.schedule[index].status = session.isComplete ? .completed : .partiallyCompleted
        }

        let prs = ProgressiveOverloadEngine.newRecords(
            from: session.setLogs,
            existing: state.personalRecords
        )
        for pr in prs {
            state.personalRecords.removeAll { $0.exerciseID == pr.exerciseID && $0.metric == pr.metric }
            state.personalRecords.append(pr)
        }
        state.lastNewRecords = prs

        if !session.isComplete {
            applyReschedule(for: workout, session: session)
        }
        save()
    }

    /// Moves anything the user missed. Safe to call repeatedly.
    func reconcileMissedWorkouts(now: Date = Date()) {
        let cal = Calendar.current
        let overdue = state.schedule.filter {
            $0.status == .upcoming && cal.startOfDay(for: $0.scheduledDate) < cal.startOfDay(for: now)
        }
        guard !overdue.isEmpty else { return }

        for workout in overdue {
            applyReschedule(for: workout, session: nil, now: now)
        }
        save()
    }

    func suggestion(for exercise: Exercise) -> ProgressiveOverloadEngine.Suggestion {
        ProgressiveOverloadEngine.suggestion(
            for: exercise,
            history: state.sessions.flatMap(\.setLogs)
        )
    }

    func substitute(_ planned: PlannedExercise, with replacement: Exercise, in workout: ScheduledWorkout) {
        guard let wIndex = state.schedule.firstIndex(where: { $0.id == workout.id }),
              let pIndex = state.schedule[wIndex].trainingDay.plannedExercises
                  .firstIndex(where: { $0.id == planned.id })
        else { return }

        state.schedule[wIndex].trainingDay.plannedExercises[pIndex].exerciseID = replacement.id
        save()
    }

    // MARK: - Internals

    private func applyReschedule(
        for workout: ScheduledWorkout,
        session: WorkoutSession?,
        now: Date = Date()
    ) {
        let outcome = RescheduleEngine.plan(
            missed: workout,
            session: session,
            schedule: state.schedule,
            now: now
        )
        if let index = state.schedule.firstIndex(where: { $0.id == workout.id }) {
            state.schedule[index].status = outcome.originalStatus
        }
        if let makeup = outcome.makeup {
            state.schedule.append(makeup)
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Losing a write should never take the app down; the next mutation retries.
            print("WorkoutStore save failed: \(error)")
        }
    }

    private static func load(from url: URL) -> AppState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppState.self, from: data)
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("gymtracker-state.json")
    }
}

// MARK: - Persisted shapes

struct WorkoutPlan: Codable {
    var daysPerWeek: Int
    var trainingDays: [TrainingDay]
}

struct AppState: Codable {
    var plan: WorkoutPlan?
    var schedule: [ScheduledWorkout] = []
    var sessions: [WorkoutSession] = []
    var personalRecords: [ProgressiveOverloadEngine.PersonalRecord] = []
    var lastNewRecords: [ProgressiveOverloadEngine.PersonalRecord] = []
}
