import Foundation
import WatchConnectivity
import WatchKit
import WidgetKit
import AscendKit

/// Watch-side session state and the phone connection.
///
/// The Watch is authoritative once a session is running on it: it drives the
/// same `SessionStateMachine` the phone uses, logs sets locally, and flushes to
/// the phone opportunistically. A workout therefore survives the phone being
/// out of range, in a locker, or flat - which is the normal case in a gym.
@MainActor
final class WatchStore: NSObject, ObservableObject {

    @Published private(set) var snapshot: WatchSync.SessionSnapshot?
    @Published private(set) var machine: SessionStateMachine?
    @Published private(set) var isReachable = false
    @Published var restRemaining = 0

    /// Logged locally first, flushed to the phone when it is listening.
    private var pendingLogs: [WatchSync.SetCompleted] = []
    private var restTimer: Timer?
    /// Live heart rate for the duration of the workout. Optional: a failure
    /// here costs the trace, not the workout.
    let workout = WatchWorkoutSession()
    let motion = WatchMotionMonitor()

    /// The upcoming plan, pushed by the phone. Held so a workout can be started
    /// from the wrist with the phone in a locker.
    @Published private(set) var plan: WatchSync.PlanSnapshot?

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    override init() {
        super.init()
        restore()
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Brings back the plan, and a session if it is recent enough to still be
    /// the one you are in.
    private func restore() {
        let restored = WatchStorage.load()
        plan = restored.plan
        pendingLogs = restored.pendingLogs
        if let snapshot = restored.session { rebuildEngine(from: snapshot) }
    }

    private func persist() {
        WatchStorage.save(plan: plan, session: snapshot, pendingLogs: pendingLogs)
    }

    /// Builds a plan on the Watch itself, for when the phone has never been
    /// reachable. Uses the same PlanBuilder the phone does, so a plan made here
    /// is indistinguishable from one made there.
    func createLocalPlan(daysPerWeek: Int) {
        let library = ExerciseLibrary.starter
        let days = PlanBuilder.trainingDays(forDaysPerWeek: daysPerWeek, library: library)
        let scheduled = PlanBuilder.schedule(days: days, startingAfter: Date())

        plan = WatchSync.PlanSnapshot(
            workouts: scheduled.map {
                WatchSync.UpcomingWorkout(
                    id: $0.id,
                    scheduledDate: $0.scheduledDate,
                    snapshot: WatchSync.SessionSnapshot(sessionID: UUID(), workout: $0)
                )
            },
            repCountingEnabled: false
        )
        persist()
        refreshComplication()
    }

    /// Rebuilds the state machine from a snapshot, shared by a fresh start and
    /// a restore after the app was terminated.
    private func rebuildEngine(from snapshot: WatchSync.SessionSnapshot) {
        self.snapshot = snapshot
        let planned = snapshot.exercises.enumerated().map { index, exercise in
            PlannedExercise(
                exercise: Exercise(
                    id: exercise.id,
                    name: exercise.name,
                    group: .chest,
                    regions: exercise.regions,
                    defaultSets: exercise.targetSets,
                    defaultReps: exercise.targetReps,
                    defaultRestSeconds: exercise.restSeconds
                ),
                orderIndex: index,
                targetSets: exercise.targetSets,
                targetReps: exercise.targetReps,
                restSeconds: exercise.restSeconds
            )
        }
        var m = SessionStateMachine(exercises: planned)
        _ = m.handle(.start)
        machine = m
    }

    var currentExercise: WatchSync.ExerciseSnapshot? {
        guard let snapshot, let machine else { return nil }
        switch machine.state {
        case let .exercising(index, _):
            return snapshot.exercises[safe: index]
        case let .resting(_, nextIndex, _):
            return snapshot.exercises[safe: nextIndex]
        case .idle, .complete:
            return nil
        }
    }

    var currentSetNumber: Int {
        guard let machine else { return 0 }
        if case let .exercising(_, setIndex) = machine.state { return setIndex + 1 }
        if case let .resting(_, _, nextSetIndex) = machine.state { return nextSetIndex + 1 }
        return 0
    }

    // MARK: - Session control

    /// Starts one of the planned workouts from the Watch itself, telling the
    /// phone afterwards rather than asking permission first - the phone may not
    /// be reachable, and that is the whole point.
    func startLocally(_ upcoming: WatchSync.UpcomingWorkout) {
        var snapshot = upcoming.snapshot
        snapshot.sessionID = UUID()
        begin(snapshot)
        send(.watchStartedSession(sessionID: snapshot.sessionID, workoutID: upcoming.id))
    }

    /// Keeps the watch face in step. Written to the Watch's own container so
    /// the complication renders with the phone nowhere nearby.
    private func refreshComplication() {
        guard let next = upcoming.first else { return }
        WatchFaceSnapshot.write(WatchFaceSnapshot(
            workoutName: next.snapshot.workoutName,
            dayLabel: Calendar.current.isDateInToday(next.scheduledDate) ? "Today" : "Next",
            exerciseCount: next.snapshot.exercises.count
        ))
        WidgetCenter.shared.reloadTimelines(ofKind: "NextWorkoutWatch")
    }

    /// Workouts still to do, soonest first.
    var upcoming: [WatchSync.UpcomingWorkout] {
        (plan?.workouts ?? []).sorted { $0.scheduledDate < $1.scheduledDate }
    }

    func begin(_ snapshot: WatchSync.SessionSnapshot) {
        pendingLogs = []
        rebuildEngine(from: snapshot)
        workout.start(sessionID: snapshot.sessionID)
        if plan?.repCountingEnabled == true { motion.start() }
        persist()
    }

    func completeSet(reps: Int, weightKg: Double?) {
        guard let snapshot, let machine, let exercise = currentExercise else { return }
        let setIndex = max(0, currentSetNumber - 1)

        apply(.setCompleted(reps: reps, weightKg: weightKg))

        let log = WatchSync.SetCompleted(
            sessionID: snapshot.sessionID,
            exerciseID: exercise.id,
            setIndex: setIndex,
            reps: reps,
            weightKg: weightKg
        )
        pendingLogs.append(log)
        persist()
        send(.setCompleted(log))
        // Counting restarts for the next set rather than accumulating.
        motion.resetForNextSet()
        _ = machine
    }

    func skipRest() {
        stopRestTimer()
        apply(.skipRest)
    }

    func end() {
        apply(.abandon)
    }

    private func apply(_ event: SessionStateMachine.Event) {
        guard var m = machine else { return }
        let effects = m.handle(event)
        machine = m

        // Resume sampling only when actually lifting again.
        if case .exercising = m.state, plan?.repCountingEnabled == true, !motion.isRunning {
            motion.start()
        }

        for effect in effects {
            switch effect {
            case let .startRestTimer(seconds):
                startRestTimer(seconds: seconds)
                // No reps happen during rest, so stop sampling motion.
                motion.pause()
            case .cancelRestTimer:
                stopRestTimer()
            case let .haptic(kind):
                play(kind)
            case let .sessionFinished(completedAll):
                finish(completedAllSets: completedAll)
            case .logSet:
                // Already recorded in completeSet, which owns the wire format.
                break
            }
        }
    }

    private func finish(completedAllSets: Bool) {
        guard let snapshot else { return }
        stopRestTimer()
        workout.stop()
        motion.stop()
        send(.sessionEnded(.init(
            sessionID: snapshot.sessionID,
            completedAllSets: completedAllSets,
            setLogs: pendingLogs
        )))
    }

    func clear() {
        snapshot = nil
        machine = nil
        pendingLogs = []
        stopRestTimer()
        persist()
    }

    // MARK: - Rest timer and haptics

    private func startRestTimer(seconds: Int) {
        restRemaining = seconds
        stopRestTimer()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.restRemaining > 0 else {
                    self.stopRestTimer()
                    self.apply(.restElapsed)
                    return
                }
                self.restRemaining -= 1
            }
        }
    }

    private func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
    }

    /// Distinct patterns so the wrist alone tells you what happened without
    /// looking at the screen - the whole point of running this on the Watch.
    private func play(_ haptic: SessionStateMachine.Haptic) {
        switch haptic {
        case .setDone:     WKInterfaceDevice.current().play(.click)
        case .restOver:    WKInterfaceDevice.current().play(.start)
        case .sessionDone: WKInterfaceDevice.current().play(.success)
        }
    }

    // MARK: - Connectivity

    func requestSnapshot() {
        send(.requestSnapshot)
    }

    func send(_ message: WatchSync.Message) {
        guard let session, session.activationState == .activated,
              let payload = try? WatchSync.dictionary(for: message)
        else { return }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                // Reachability can drop mid-set. Queue it instead of losing it -
                // transferUserInfo is delivered whenever the phone next appears.
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }
}

extension WatchStore: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            if state == .activated { self.requestSnapshot() }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isReachable = session.isReachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }

    private nonisolated func handle(_ dictionary: [String: Any]) {
        guard let message = try? WatchSync.message(from: dictionary) else { return }
        Task { @MainActor in
            switch message {
            case let .startSession(snapshot):
                self.begin(snapshot)
            case .noActiveSession:
                self.clear()
            case let .planUpdated(plan):
                self.plan = plan
                self.persist()
                self.refreshComplication()
            case .setCompleted, .sessionEnded, .requestSnapshot, .watchStartedSession:
                // Phone-bound messages; nothing for the Watch to do.
                break
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
