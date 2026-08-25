import Foundation
import HealthKit
import AscendKit

/// Runs an `HKWorkoutSession` for the duration of a workout.
///
/// This is what makes heart rate genuinely live: while the session is active
/// watchOS streams samples every few seconds and keeps the app running with the
/// wrist down. It also puts the workout in the Activity rings, which is what
/// people expect from any app that calls itself a workout app.
///
/// Blood oxygen and wrist temperature are deliberately absent here. watchOS
/// generally suppresses SpO2 during a workout and only writes wrist temperature
/// overnight, so neither can be streamed - the phone reads those separately as
/// dated, clearly-labelled readings.
@MainActor
final class WatchWorkoutSession: NSObject, ObservableObject {

    @Published private(set) var currentHeartRate: Int?
    @Published private(set) var averageHeartRate: Int?
    @Published private(set) var isRunning = false

    /// Every heart-rate sample seen, handed to the phone when the session ends.
    private(set) var samples: [VitalsSample] = []

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var sessionID: UUID?

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        for identifier: HKQuantityTypeIdentifier in [.heartRate, .activeEnergyBurned] {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    func requestAuthorisation() async -> Bool {
        guard Self.isAvailable else { return false }
        do {
            try await store.requestAuthorization(
                toShare: [HKObjectType.workoutType()],
                read: readTypes
            )
            return true
        } catch {
            return false
        }
    }

    func start(sessionID: UUID) {
        guard Self.isAvailable, session == nil else { return }
        self.sessionID = sessionID
        samples = []

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { [weak self] _, _ in
                Task { @MainActor in self?.isRunning = true }
            }

            self.session = session
            self.builder = builder
        } catch {
            // A failed workout session must not take the workout down with it -
            // the user can still log sets, they just lose the heart-rate trace.
            self.session = nil
            self.builder = nil
        }
    }

    func stop() {
        guard let session, let builder else { return }
        let end = Date()
        session.end()
        // `self` is captured weakly on the Task rather than on the outer
        // closure: capturing it further out makes it a mutable capture shared
        // across two escaping HealthKit callbacks, which is a data race.
        builder.endCollection(withEnd: end) { _, _ in
            builder.finishWorkout { _, _ in
                Task { @MainActor [weak self] in
                    self?.session = nil
                    self?.builder = nil
                    self?.isRunning = false
                }
            }
        }
    }

    private func record(_ statistics: HKStatistics?) {
        guard let statistics,
              statistics.quantityType == HKQuantityType.quantityType(forIdentifier: .heartRate)
        else { return }

        let unit = HKUnit.count().unitDivided(by: .minute())
        if let recent = statistics.mostRecentQuantity()?.doubleValue(for: unit) {
            currentHeartRate = Int(recent.rounded())
            samples.append(VitalsSample(
                sessionID: sessionID,
                kind: .heartRate,
                value: recent,
                source: .liveDuringWorkout
            ))
        }
        if let average = statistics.averageQuantity()?.doubleValue(for: unit) {
            averageHeartRate = Int(average.rounded())
        }
    }
}

extension WatchWorkoutSession: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            self.isRunning = (toState == .running)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.isRunning = false
            self.session = nil
            self.builder = nil
        }
    }
}

extension WatchWorkoutSession: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = workoutBuilder.statistics(for: quantityType)
            Task { @MainActor in self.record(statistics) }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
