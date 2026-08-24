import Foundation
import AscendKit

/// Everything the app knows, held in one place and written to a JSON file.
///
/// Phase 1 uses a Codable snapshot rather than Core Data: every AscendKit type is
/// already `Codable`, this is a single-user local app, and it avoids hand-
/// authoring an `.xcdatamodeld`. Swapping in Core Data later only touches
/// `load()` and `save()` - nothing above this layer knows how it is stored.
@MainActor
final class AppStore: ObservableObject {

    // MARK: - Persisted state

    @Published internal(set) var plan: WorkoutPlan?
    /// internal(set) rather than private(set) so the plan-editing extension in
    /// AppStore+Editing.swift can write it - `private` is file-scoped in Swift.
    /// Mutate through the editing methods, not directly from views.
    @Published internal(set) var schedule: [ScheduledWorkout] = []
    @Published internal(set) var sessions: [WorkoutSession] = []
    @Published private(set) var records: [ProgressiveOverloadEngine.PersonalRecord] = []
    @Published private(set) var intake: [IntakeEntry] = []
    @Published private(set) var vitals: [VitalsSample] = []
    /// Exercises the user created, kept separate from the seeded library so a
    /// future library update cannot clobber them.
    @Published var customExercises: [Exercise] = []
    @Published internal(set) var measurements: [BodyMeasurement] = []
    /// Workouts recorded by other apps, kept apart from our own sessions so
    /// they can never be confused with them.
    @Published internal(set) var importedWorkouts: [ImportedWorkout] = []
    /// Today's protein and water totals as Health sees them, including other
    /// apps. Not persisted - it is a view of Health, re-read each time.
    @Published internal(set) var externalIntake: [IntakeKind: Double] = [:]
    /// Guards against registering the Health observer more than once.
    internal var isObservingHealth = false
    /// Whether plan edits apply to one day or the whole recurring series.
    /// Series is the default because "edit my Push day" almost always means
    /// every Push day.
    @Published var editScope: PlanEditor.Scope = .series
    /// How many future days the last edit reached, for a confirmation line.
    @Published var lastEditAffectedFutureDays = 0
    @Published var settings = FeatureSettings()

    let library = ExerciseLibrary.starter

    // MARK: - Live session

    @Published var activeSession: WorkoutSession?
    @Published var activeWorkout: ScheduledWorkout?
    @Published var machine: SessionStateMachine?
    /// Drives the session screen. Owned by the store rather than the view so a
    /// session started anywhere - phone, Watch, or restored at launch - puts
    /// the phone into the session UI instead of offering to start another.
    @Published var isSessionPresented = false
    let watch = PhoneSessionManager()
    let health = HealthKitManager()
    let liveActivity = LiveActivityController()
    let cloud = CloudBackup()
    /// PRs set by the session that just ended, shown on the summary screen.
    @Published var lastSessionRecords: [ProgressiveOverloadEngine.PersonalRecord] = []

    // MARK: - Lifecycle

    init() {
        load()
        watch.store = self
        #if DEBUG
        applyLaunchArgumentsForTesting()
        #endif
    }

    #if DEBUG
    /// Test hooks so the phone/Watch pair can be driven without tapping through
    /// onboarding by hand:
    ///   -reset            start from a clean slate
    ///   -autoplan         create a 4 day plan
    ///   -autostart        begin the next workout, which pushes it to the Watch
    private func applyLaunchArgumentsForTesting() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-reset") { reset() }
        if arguments.contains("-autoplan"), plan == nil { createPlan(daysPerWeek: 4) }
        if arguments.contains("-autostart"), let next = nextWorkout { startSession(for: next) }
        // Simulator has no Health data, so there is otherwise no way to see how
        // an outside workout renders in history.
        if arguments.contains("-fakehealth") {
            importedWorkouts = [
                ImportedWorkout(
                    healthKitID: UUID(), activityName: "Run",
                    startedAt: Date().addingTimeInterval(-86_400),
                    duration: 2_400, sourceName: "com.strava.Strava"
                )
            ]
        }
    }
    #endif

    var hasOnboarded: Bool { plan != nil }

    /// All logged sets across every session, which is what the progression
    /// engine reads.
    var allSetLogs: [SetLog] {
        sessions.flatMap(\.setLogs) + (activeSession?.setLogs ?? [])
    }

    // MARK: - Onboarding

    func createPlan(daysPerWeek: Int) {
        let days = PlanBuilder.trainingDays(forDaysPerWeek: daysPerWeek, library: library)
        let newPlan = WorkoutPlan(daysPerWeek: daysPerWeek, trainingDays: days)
        plan = newPlan
        schedule = PlanBuilder.schedule(days: days, startingAfter: Date())
        saveAndSync()
    }

    /// Persists and re-syncs everything downstream of the plan. Use only when
    /// the schedule, plan or settings actually changed.
    func saveAndSync() {
        save()
        syncNotifications()
    }

    /// Builds a plan from the onboarding answers, using only exercises the
    /// user's equipment allows.
    func createRecommendedPlan(_ answers: PlanRecommender.Answers) {
        let recommendation = PlanRecommender.recommend(answers)
        let usable = PlanRecommender.library(library, filteredFor: answers.equipment)

        let days = PlanBuilder.trainingDays(
            forDaysPerWeek: recommendation.daysPerWeek,
            library: usable
        )
        plan = WorkoutPlan(daysPerWeek: recommendation.daysPerWeek, trainingDays: days)
        schedule = PlanBuilder.schedule(days: days, startingAfter: Date())
        settings.equipment = answers.equipment
        settings.experience = answers.experience
        saveAndSync()
    }

    /// Re-registers reminders and re-pushes the plan to the Watch. Expensive -
    /// call it when the schedule or settings change, not on every write.
    func syncNotifications() {
        NotificationScheduler.sync(schedule: schedule, settings: settings)
        NotificationScheduler.syncIntakeReminders(settings: settings)
        pushPlanToWatch()
    }

    /// Wipes everything and returns to onboarding.
    func reset() {
        plan = nil
        schedule = []
        sessions = []
        records = []
        intake = []
        vitals = []
        customExercises = []
        measurements = []
        importedWorkouts = []
        activeSession = nil
        machine = nil
        settings = FeatureSettings()
        saveAndSync()
    }

    // MARK: - Today

    /// The next workout still to be done, soonest first.
    var nextWorkout: ScheduledWorkout? {
        schedule
            .filter { $0.status == .upcoming || $0.status == .partiallyCompleted }
            .min { $0.scheduledDate < $1.scheduledDate }
    }

    var thisWeek: [ScheduledWorkout] {
        let cal = Calendar.current
        guard let week = cal.dateInterval(of: .weekOfYear, for: Date()) else { return schedule }
        return schedule
            .filter { week.contains($0.scheduledDate) }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    // MARK: - Session control

    func startSession(for workout: ScheduledWorkout) {
        var session = WorkoutSession(scheduledWorkoutID: workout.id)
        session.startedAt = Date()
        activeSession = session
        activeWorkout = workout

        var m = SessionStateMachine(exercises: workout.trainingDay.plannedExercises)
        _ = m.handle(.start)
        machine = m
        isSessionPresented = true

        watch.sendSessionStart(watchSnapshot(sessionID: session.id, workout: workout))
        liveActivity.start(
            workoutName: workout.trainingDay.name,
            bodyMapKey: workout.trainingDay.bodyMapKey,
            state: activityState()
        )
        publishWidgetSnapshot()
    }

    // MARK: - Watch link

    /// Snapshot of whatever is in progress, or nil when nothing is.
    func currentWatchSnapshot() -> WatchSync.SessionSnapshot? {
        guard let session = activeSession, let workout = activeWorkout else { return nil }
        return watchSnapshot(sessionID: session.id, workout: workout)
    }

    private func watchSnapshot(sessionID: UUID, workout: ScheduledWorkout) -> WatchSync.SessionSnapshot {
        // Carry the progression targets across so the Watch can pre-fill its
        // inputs without asking the phone again mid-set.
        var suggestions: [UUID: Double] = [:]
        for planned in workout.trainingDay.plannedExercises {
            if let weight = suggestion(for: planned.exercise).weight {
                suggestions[planned.exercise.id] = weight
            }
        }
        return WatchSync.SessionSnapshot(sessionID: sessionID, workout: workout, suggestions: suggestions)
    }

    /// The Watch started a workout on its own. Adopt it so the phone mirrors
    /// the same session rather than offering to start a second one.
    func adoptWatchSession(sessionID: UUID, workoutID: UUID) {
        guard activeSession == nil,
              let workout = schedule.first(where: { $0.id == workoutID })
        else { return }

        var session = WorkoutSession(id: sessionID, scheduledWorkoutID: workoutID)
        session.startedAt = Date()
        activeSession = session
        activeWorkout = workout

        var m = SessionStateMachine(exercises: workout.trainingDay.plannedExercises)
        _ = m.handle(.start)
        machine = m
        isSessionPresented = true
    }

    /// Everything still to do, pushed to the Watch so it can work alone.
    func pushPlanToWatch() {
        let upcoming = schedule
            .filter { $0.status == .upcoming || $0.status == .partiallyCompleted }
            .sorted { $0.scheduledDate < $1.scheduledDate }
            .prefix(4)
            .map { workout in
                WatchSync.UpcomingWorkout(
                    id: workout.id,
                    scheduledDate: workout.scheduledDate,
                    snapshot: watchSnapshot(sessionID: UUID(), workout: workout)
                )
            }
        watch.sendPlan(WatchSync.PlanSnapshot(
            workouts: Array(upcoming),
            repCountingEnabled: settings.repCountingEnabled
        ))
    }

    /// A set logged on the Watch. Ignored if already recorded, because a
    /// message can arrive twice once reachability recovers.
    func applyWatchSet(_ log: WatchSync.SetCompleted) {
        guard var session = activeSession, session.id == log.sessionID else { return }
        let alreadyLogged = session.setLogs.contains {
            $0.exerciseID == log.exerciseID && $0.setIndex == log.setIndex
        }
        guard !alreadyLogged else { return }

        session.setLogs.append(SetLog(
            exerciseID: log.exerciseID,
            setIndex: log.setIndex,
            reps: log.reps,
            weightKg: log.weightKg,
            completedAt: log.completedAt
        ))
        activeSession = session
    }

    /// The Watch finished. Replay anything the phone missed, then close the
    /// session through the same path a phone-run workout takes.
    func applyWatchSessionEnd(_ payload: WatchSync.SessionEnded) {
        guard let session = activeSession, session.id == payload.sessionID else { return }
        for log in payload.setLogs { applyWatchSet(log) }
        machine = nil
        finish(completedAllSets: payload.completedAllSets)
    }

    /// Applies an event to the state machine and folds the resulting effects
    /// back into the session. Returns the effects so the view can fire haptics
    /// and timers.
    @discardableResult
    func send(_ event: SessionStateMachine.Event) -> [SessionStateMachine.Effect] {
        guard var m = machine else { return [] }
        let effects = m.handle(event)
        machine = m
        // One update per real transition; the Lock Screen ticks its own clock.
        liveActivity.update(activityState())

        for effect in effects {
            switch effect {
            case let .logSet(exerciseID, setIndex, reps, weightKg):
                activeSession?.setLogs.append(
                    SetLog(exerciseID: exerciseID, setIndex: setIndex, reps: reps, weightKg: weightKg)
                )
            case let .sessionFinished(completedAll):
                finish(completedAllSets: completedAll)
            case .startRestTimer, .cancelRestTimer, .haptic:
                break
            }
        }
        return effects
    }

    /// Current state machine position, shaped for the Live Activity.
    func activityState() -> WorkoutActivityState {
        let exercises = machine?.exercises ?? []
        let total = exercises.reduce(0) { $0 + $1.targetSets }
        let done = activeSession?.setLogs.count ?? 0

        guard let machine else {
            return WorkoutActivityState(
                phase: .exercising, exerciseName: "", setNumber: 0, totalSets: 0,
                exerciseNumber: 0, totalExercises: exercises.count,
                completedSets: done, totalPlannedSets: total
            )
        }

        switch machine.state {
        case let .exercising(exerciseIndex, setIndex):
            let planned = exercises[exerciseIndex]
            return WorkoutActivityState(
                phase: .exercising,
                exerciseName: planned.exercise.name,
                setNumber: setIndex + 1,
                totalSets: planned.targetSets,
                exerciseNumber: exerciseIndex + 1,
                totalExercises: exercises.count,
                completedSets: done,
                totalPlannedSets: total
            )
        case let .resting(seconds, nextExerciseIndex, nextSetIndex):
            let planned = exercises[nextExerciseIndex]
            return WorkoutActivityState(
                phase: .resting,
                exerciseName: planned.exercise.name,
                setNumber: nextSetIndex + 1,
                totalSets: planned.targetSets,
                exerciseNumber: nextExerciseIndex + 1,
                totalExercises: exercises.count,
                // Absolute end time so the Lock Screen ticks the clock itself.
                restEndsAt: Date().addingTimeInterval(Double(seconds)),
                completedSets: done,
                totalPlannedSets: total
            )
        case .idle, .complete:
            return WorkoutActivityState(
                phase: .exercising, exerciseName: "", setNumber: 0, totalSets: 0,
                exerciseNumber: 0, totalExercises: exercises.count,
                completedSets: done, totalPlannedSets: total
            )
        }
    }

    /// Applies a button press that came from the Lock Screen. The widget
    /// extension cannot touch session state directly, so it leaves a note and
    /// the app replays it through the normal path.
    func applyPendingWidgetCommand() {
        guard let command = SharedSessionCommands.take() else { return }
        switch command {
        case .startWorkout:
            // From Siri, so there may be no session yet - that is the point.
            if activeSession == nil, let next = nextWorkout { startSession(for: next) }
        case let .logWater(millilitres):
            guard settings.waterTrackingEnabled else { return }
            logIntake(kind: .water, amount: Double(millilitres))
        case .skipRest:
            guard machine != nil else { return }
            send(.skipRest)
        case .logSet:
            guard machine != nil else { return }
            let planned = machine?.currentExercise
            send(.setCompleted(reps: planned?.targetReps ?? 10, weightKg: nil))
        }
    }

    /// Small snapshot for the home screen widget.
    func publishWidgetSnapshot() {
        guard let next = nextWorkout else { return }
        let week = thisWeek
        WidgetSnapshot.write(WidgetSnapshot(
            workoutName: next.trainingDay.name,
            dayLabel: dayLabel(for: next.scheduledDate),
            groups: next.trainingDay.groups.map(\.displayName),
            doneThisWeek: week.filter { $0.status == .completed }.count,
            totalThisWeek: week.count,
            streak: currentStreak
        ))
        LiveActivityController.reloadWidget()
    }

    /// Consecutive days ending today or yesterday with a completed session.
    var currentStreak: Int {
        let cal = Calendar.current
        let days = Set(sessions.filter(\.isComplete).map { cal.startOfDay(for: $0.startedAt) })
        guard !days.isEmpty else { return 0 }

        var cursor = cal.startOfDay(for: Date())
        if !days.contains(cursor) {
            // Yesterday still counts - a streak should not break until a day is
            // fully missed.
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private func dayLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func finish(completedAllSets: Bool) {
        guard var session = activeSession else { return }
        session.endedAt = Date()
        session.isComplete = completedAllSets
        session.totalActiveSeconds = session.endedAt!.timeIntervalSince(session.startedAt)

        // newRecords returns only what was beaten, so merge rather than assign.
        let beaten = ProgressiveOverloadEngine.newRecords(from: session.setLogs, existing: records)
        lastSessionRecords = beaten
        for record in beaten {
            if let i = records.firstIndex(where: {
                $0.exerciseID == record.exerciseID && $0.metric == record.metric
            }) {
                records[i] = record
            } else {
                records.append(record)
            }
        }
        sessions.append(session)

        if let workoutID = session.scheduledWorkoutID,
           let index = schedule.firstIndex(where: { $0.id == workoutID }) {
            schedule[index].status = completedAllSets ? .completed : .partiallyCompleted

            // An unfinished session is exactly the signal the rescheduler wants.
            if !completedAllSets {
                let outcome = RescheduleEngine.plan(
                    missed: schedule[index],
                    session: session,
                    schedule: schedule,
                    now: Date()
                )
                schedule[index].status = outcome.originalStatus
                if let makeup = outcome.makeup {
                    schedule.append(makeup)
                }
            }
        }

        let finished = session
        activeSession = nil
        activeWorkout = nil
        machine = nil
        watch.sendNoActiveSession()
        liveActivity.end()
        publishWidgetSnapshot()
        // Finishing changes the schedule - status, and possibly a makeup day -
        // so this is one of the few writes that genuinely needs the full sync.
        saveAndSync()

        if settings.healthKitEnabled {
            Task {
                await health.save(finished, name: activeWorkout?.trainingDay.name ?? "Workout")
                await refreshVitals(for: finished)
            }
        }
    }

    /// Next-session target for an exercise, from its whole logged history.
    func suggestion(for exercise: Exercise) -> ProgressiveOverloadEngine.Suggestion {
        ProgressiveOverloadEngine.suggestion(for: exercise, history: allSetLogs)
    }

    func swap(_ planned: PlannedExercise, to replacement: Exercise, in workout: ScheduledWorkout) {
        guard let wIndex = schedule.firstIndex(where: { $0.id == workout.id }),
              let eIndex = schedule[wIndex].trainingDay.plannedExercises
                .firstIndex(where: { $0.id == planned.id })
        else { return }

        schedule[wIndex].trainingDay.plannedExercises[eIndex] = PlannedExercise(
            id: planned.id,
            exercise: replacement,
            orderIndex: planned.orderIndex,
            targetSets: planned.targetSets,
            targetReps: planned.targetReps,
            restSeconds: planned.restSeconds
        )
        save()
    }

    // MARK: - Vitals

    /// Pulls whatever Health has for a finished session, plus the latest
    /// spot-check and overnight readings. Each is stored with its own source so
    /// the UI can label it honestly rather than implying everything is live.
    func refreshVitals(for session: WorkoutSession) async {
        guard settings.healthKitEnabled, health.isAuthorised else { return }

        var collected = await health.heartRate(
            from: session.startedAt,
            to: session.endedAt ?? Date(),
            sessionID: session.id
        )
        if let oxygen = await health.latestBloodOxygen() { collected.append(oxygen) }
        if let temperature = await health.latestWristTemperature() { collected.append(temperature) }

        guard !collected.isEmpty else { return }
        vitals.append(contentsOf: collected)
        save()
    }

    /// Kinds that have actually produced readings. Drives what the Vitals
    /// section shows, rather than assuming a Watch generation.
    var availableVitals: Set<VitalsKind> {
        VitalsSummary.availableKinds(in: vitals)
    }

    func heartRateSummary(for session: WorkoutSession) -> (average: Int, peak: Int)? {
        VitalsSummary.heartRate(for: session.id, in: vitals)
    }

    func latestVital(_ kind: VitalsKind) -> VitalsSample? {
        VitalsSummary.latest(kind, in: vitals)
    }

    var weeklyAverageHeartRate: Int? {
        let cal = Calendar.current
        guard let week = cal.dateInterval(of: .weekOfYear, for: Date()) else { return nil }
        return VitalsSummary.averageHeartRate(in: vitals, from: week.start, to: week.end)
    }

    // MARK: - Intake

    func logIntake(kind: IntakeKind, amount: Double) {
        guard amount > 0 else { return }
        let entry = IntakeEntry(kind: kind, amount: amount)
        intake.append(entry)
        save()
        if settings.healthKitEnabled {
            Task { await health.save(intake: entry) }
        }
    }

    func removeIntake(_ entry: IntakeEntry) {
        intake.removeAll { $0.id == entry.id }
        save()
    }

    func todayTotal(for kind: IntakeKind) -> Double {
        IntakeTracker.total(intake, kind: kind, on: Date())
    }

    func goal(for kind: IntakeKind) -> Double {
        switch kind {
        case .protein: return settings.proteinGoal
        case .water:   return settings.waterGoal
        }
    }

    func lastEntry(for kind: IntakeKind) -> IntakeEntry? {
        intake.filter { $0.kind == kind }.max { $0.loggedAt < $1.loggedAt }
    }

    func weeklyTotals(for kind: IntakeKind) -> [(date: Date, total: Double)] {
        IntakeTracker.dailyTotals(intake, kind: kind, endingOn: Date(), days: 7)
    }

    /// True when either nutrient is on, which decides whether the Intake tab
    /// exists at all.
    var nutritionEnabled: Bool {
        settings.proteinTrackingEnabled || settings.waterTrackingEnabled
    }

    // MARK: - Persistence

    struct Snapshot: Codable {
        var plan: WorkoutPlan?
        var schedule: [ScheduledWorkout]
        var sessions: [WorkoutSession]
        var records: [ProgressiveOverloadEngine.PersonalRecord]
        var settings: FeatureSettings
        var intake: [IntakeEntry]?
        var vitals: [VitalsSample]?
        var customExercises: [Exercise]?
        var measurements: [BodyMeasurement]?
        var importedWorkouts: [ImportedWorkout]?
    }

    private var fileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gymtracker.json")
    }

    func makeSnapshot() -> Snapshot {
        Snapshot(plan: plan, schedule: schedule, sessions: sessions,
                 records: records, settings: settings, intake: intake,
                 vitals: vitals, customExercises: customExercises,
                 measurements: measurements, importedWorkouts: importedWorkouts)
    }

    func apply(_ snapshot: Snapshot) {
        plan = snapshot.plan
        schedule = snapshot.schedule
        sessions = snapshot.sessions
        records = snapshot.records
        settings = snapshot.settings
        intake = snapshot.intake ?? []
        vitals = snapshot.vitals ?? []
        customExercises = snapshot.customExercises ?? []
        measurements = snapshot.measurements ?? []
        importedWorkouts = snapshot.importedWorkouts ?? []
    }

    /// Persists only.
    ///
    /// Deliberately does *not* re-register notifications or push the plan to
    /// the Watch. Those are expensive - a full notification rebuild plus a
    /// whole-plan WCSession transfer - and logging a set changes neither. A
    /// twelve set workout used to do both twelve times over.
    func save() {
        let snapshot = makeSnapshot()
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Losing a write is not worth crashing over on a personal app; the
            // next save will pick it up.
            print("save failed: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        apply(snapshot)
    }
}

/// Opt-in feature flags. Everything defaults to off - nothing is requested at
/// first launch, each toggle asks for its own permission when switched on.
struct FeatureSettings: Codable, Equatable {
    var notificationsEnabled = false
    var notificationLeadHours: Double = 3
    var healthKitEnabled = false
    var proteinTrackingEnabled = false
    var waterTrackingEnabled = false
    var proteinGoal = IntakeKind.protein.defaultGoal
    var waterGoal = IntakeKind.water.defaultGoal
    /// How many times a day to prompt logging, when either nutrient is on.
    var intakeRemindersPerDay = 4
    /// Scheduled deload weeks. Off by default - it changes your targets, so it
    /// should be a choice rather than something the app does behind your back.
    var periodization = PeriodizationEngine.Settings()
    /// Automatic rep counting from wrist motion during a Watch workout.
    var repCountingEnabled = false
    /// Kept from onboarding so exercise suggestions and swaps stay within what
    /// the user can actually reach.
    var equipment: PlanRecommender.Equipment = .fullGym
    var experience: PlanRecommender.Experience = .returning
}
