import Foundation
import HealthKit
import AscendKit

/// Phone-side Health access: authorisation, and reading back the vitals the
/// system recorded.
///
/// The live heart-rate stream comes from the Watch (see `WatchWorkoutSession`);
/// this side asks for permission, pulls spot-check and overnight readings, and
/// answers "is there any data of this kind at all", which is how the UI decides
/// what to show rather than guessing from a Watch model number.
@MainActor
final class HealthKitManager: ObservableObject {

    @Published private(set) var isAuthorised = false
    @Published private(set) var lastError: String?

    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Requested for every type regardless of the paired Watch. Asking for a
    /// type the hardware cannot produce is harmless - it simply never returns
    /// samples - and avoids hardcoding device checks that go stale.
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        for identifier: HKQuantityTypeIdentifier in [
            .heartRate, .oxygenSaturation, .activeEnergyBurned,
            // Read back what other apps and scales record, so this app is not
            // an island inside Health.
            .bodyMass, .bodyFatPercentage, .waistCircumference,
            .dietaryProtein, .dietaryWater
        ] {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        // Wrist temperature only exists on newer OS versions and hardware.
        if #available(iOS 16.0, *),
           let temperature = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
            types.insert(temperature)
        }
        return types
    }

    private var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        for identifier: HKQuantityTypeIdentifier in [.dietaryProtein, .dietaryWater] {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    func requestAuthorisation() async -> Bool {
        guard Self.isAvailable else {
            lastError = "Health data is not available on this device."
            return false
        }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            isAuthorised = true
            return true
        } catch {
            lastError = error.localizedDescription
            isAuthorised = false
            return false
        }
    }

    // MARK: - Reading

    /// Most recent blood oxygen reading, whenever the system happened to take
    /// one. Explicitly not live - watchOS generally suppresses these during a
    /// workout, so this is the last spot check, not a current value.
    func latestBloodOxygen() async -> VitalsSample? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else { return nil }
        guard let sample = await mostRecent(of: type) else { return nil }
        return VitalsSample(
            kind: .bloodOxygen,
            value: sample.quantity.doubleValue(for: .percent()) * 100,
            recordedAt: sample.endDate,
            source: .periodicSpotCheck
        )
    }

    /// Last night's wrist temperature. Written once per night during sleep and
    /// never available mid-workout, so it is shown as its own dated card.
    func latestWristTemperature() async -> VitalsSample? {
        guard #available(iOS 16.0, *),
              let type = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature),
              let sample = await mostRecent(of: type)
        else { return nil }
        return VitalsSample(
            kind: .wristTemperature,
            value: sample.quantity.doubleValue(for: .degreeCelsius()),
            recordedAt: sample.endDate,
            source: .overnightOnly
        )
    }

    /// Heart-rate samples recorded across a session's window, so a workout run
    /// on the Watch still shows its trace on the phone.
    func heartRate(from start: Date, to end: Date, sessionID: UUID) async -> [VitalsSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let unit = HKUnit.count().unitDivided(by: .minute())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
            ) { _, samples, _ in
                let mapped = (samples as? [HKQuantitySample] ?? []).map {
                    VitalsSample(
                        sessionID: sessionID,
                        kind: .heartRate,
                        value: $0.quantity.doubleValue(for: unit),
                        recordedAt: $0.endDate,
                        source: .liveDuringWorkout
                    )
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    private func mostRecent(of type: HKQuantityType) async -> HKQuantitySample? {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample])?.first)
            }
            store.execute(query)
        }
    }

    // MARK: - Importing

    /// Workouts Health knows about. Filtering out our own happens in
    /// `HealthSync`, which is unit tested - this only fetches.
    func importableWorkouts(since: Date) async -> [ImportedWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 100,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                let workouts = (samples as? [HKWorkout] ?? []).map { workout in
                    ImportedWorkout(
                        healthKitID: workout.uuid,
                        activityName: Self.name(for: workout.workoutActivityType),
                        startedAt: workout.startDate,
                        duration: workout.duration,
                        // The bundle identifier, not the display name - it is
                        // what reliably identifies our own writes.
                        sourceName: workout.sourceRevision.source.bundleIdentifier,
                        energyKilocalories: nil
                    )
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    /// Latest body measurements recorded anywhere - a smart scale, another app,
    /// or the Health app itself.
    func importableMeasurements() async -> [BodyMeasurement] {
        var found: [BodyMeasurement] = []

        let mapping: [(HKQuantityTypeIdentifier, MeasurementKind, HKUnit)] = [
            (.bodyMass, .bodyWeight, .gramUnit(with: .kilo)),
            (.bodyFatPercentage, .bodyFat, .percent()),
            (.waistCircumference, .waist, .meterUnit(with: .centi))
        ]

        for (identifier, kind, unit) in mapping {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier),
                  let sample = await mostRecent(of: type)
            else { continue }

            var value = sample.quantity.doubleValue(for: unit)
            if kind == .bodyFat { value *= 100 }

            found.append(BodyMeasurement(kind: kind, value: value, recordedAt: sample.endDate))
        }
        return found
    }

    /// Protein and water logged elsewhere today, so the intake totals reflect
    /// everything rather than only what was typed into this app.
    func dietaryTotalToday(_ kind: IntakeKind) async -> Double? {
        let identifier: HKQuantityTypeIdentifier = kind == .protein ? .dietaryProtein : .dietaryWater
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let unit: HKUnit = kind == .protein ? .gram() : .literUnit(with: .milli)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Asks Health to wake the app when new workouts land, so imports happen
    /// without the user opening the app first.
    ///
    /// Best effort by design. iOS decides when to deliver and may not for
    /// hours, and true background wake-up additionally needs the HealthKit
    /// background-delivery entitlement, which a free provisioning profile
    /// cannot carry - without it the observer only fires while the app runs.
    /// Nothing depends on it either way: the app also imports on every
    /// foreground, which is what actually keeps history current.
    func enableBackgroundDelivery(onChange: @escaping () -> Void) {
        let type = HKObjectType.workoutType()
        store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }

        let observer = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in
            onChange()
            // Must always be called, or HealthKit stops delivering.
            completion()
        }
        store.execute(observer)
    }

    private static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength training"
        case .running:      return "Run"
        case .walking:      return "Walk"
        case .cycling:      return "Cycle"
        case .swimming:     return "Swim"
        case .highIntensityIntervalTraining: return "HIIT"
        case .yoga:         return "Yoga"
        case .rowing:       return "Row"
        case .hiking:       return "Hike"
        default:            return "Workout"
        }
    }

    // MARK: - Writing

    /// Mirrors a finished session into Health so it lands in the Activity rings
    /// and shows up alongside every other workout, which is what people expect
    /// from anything calling itself a workout app.
    func save(_ session: WorkoutSession, name: String) async {
        guard isAuthorised else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: session.startedAt)
            try await builder.endCollection(at: session.endedAt ?? Date())
            _ = try await builder.finishWorkout()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Optional mirroring of intake, behind its own toggle - writing dietary
    /// data is a separate authorisation from reading vitals.
    func save(intake entry: IntakeEntry) async {
        guard isAuthorised else { return }
        let identifier: HKQuantityTypeIdentifier = entry.kind == .protein ? .dietaryProtein : .dietaryWater
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return }

        let quantity = entry.kind == .protein
            ? HKQuantity(unit: .gram(), doubleValue: entry.amount)
            : HKQuantity(unit: .literUnit(with: .milli), doubleValue: entry.amount)

        let sample = HKQuantitySample(
            type: type, quantity: quantity,
            start: entry.loggedAt, end: entry.loggedAt
        )
        do {
            try await store.save(sample)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
