import SwiftUI
import AscendKit

/// Weekly picture: what is done, what is still owed, and which muscle groups
/// have been covered.
struct SummaryView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    stats
                    coverage
                    restDays
                    if store.settings.healthKitEnabled { vitalsSection }
                    NavigationLink {
                        MeasurementsView()
                    } label: {
                        HStack {
                            Label("Body measurements", systemImage: "figure")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    RegionBalanceView()
                    if !store.records.isEmpty { personalBests }
                }
                .padding(20)
            }
            .navigationTitle("This week")
        }
    }

    private var week: [ScheduledWorkout] { store.thisWeek }
    private var done: Int { week.filter { $0.status == .completed }.count }

    private var stats: some View {
        HStack(spacing: 12) {
            statTile(label: "Sessions", value: "\(done) / \(week.count)")
            statTile(label: "Time trained", value: timeTrained)
        }
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var timeTrained: String {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return "0m" }
        let seconds = store.sessions
            .filter { interval.contains($0.startedAt) }
            .reduce(0) { $0 + $1.totalActiveSeconds }
        let minutes = Int(seconds) / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// Regions trained this week versus everything the plan covers.
    private var coverage: some View {
        let trained = week
            .filter { $0.status == .completed }
            .reduce(into: Set<MuscleRegion>()) { $0.formUnion($1.trainingDay.regions) }
        let planned = week
            .reduce(into: Set<MuscleRegion>()) { $0.formUnion($1.trainingDay.regions) }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Muscle groups")
                .font(.headline)

            BodyMapView(regions: trained)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

            ForEach(MuscleGroup.allCases, id: \.self) { group in
                let groupRegions = group.regions
                let isDone = !groupRegions.isDisjoint(with: trained)
                let isPlanned = !groupRegions.isDisjoint(with: planned)
                if isPlanned {
                    HStack {
                        Text(group.displayName)
                            .font(.subheadline)
                        Spacer()
                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        } else {
                            Text("Pending")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var restDays: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rest between sessions")
                .font(.headline)
            Text(restText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var restText: String {
        let dates = week
            .filter { $0.status == .completed }
            .map(\.scheduledDate)
            .sorted()
        guard dates.count > 1 else { return "Not enough sessions yet to measure." }

        let cal = Calendar.current
        let gaps = zip(dates, dates.dropFirst()).compactMap {
            cal.dateComponents([.day], from: $0, to: $1).day
        }
        guard !gaps.isEmpty else { return "Not enough sessions yet to measure." }
        let average = Double(gaps.reduce(0, +)) / Double(gaps.count)
        return "Averaging \(average.formatted(.number.precision(.fractionLength(0...1)))) days between sessions."
    }

    /// Only kinds that have actually produced readings appear. There is no
    /// reliable way to ask which Watch is paired, so an absent section means
    /// "no data yet" rather than a claim about your hardware.
    @ViewBuilder
    private var vitalsSection: some View {
        let available = store.availableVitals

        VStack(alignment: .leading, spacing: 10) {
            Text("Vitals")
                .font(.headline)

            if available.isEmpty {
                Text("No readings yet. Heart rate arrives once you run a workout with your Watch on.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if let average = store.weeklyAverageHeartRate {
                    vitalRow(
                        kind: .heartRate,
                        value: "\(average) bpm",
                        detail: "Average across this week's workouts."
                    )
                }
                if available.contains(.bloodOxygen), let sample = store.latestVital(.bloodOxygen) {
                    vitalRow(
                        kind: .bloodOxygen,
                        value: "\(sample.value.formatted(.number.precision(.fractionLength(0))))%",
                        detail: "\(sample.source.caveat) Last: \(sample.recordedAt.formatted(date: .abbreviated, time: .shortened))."
                    )
                }
                if available.contains(.wristTemperature), let sample = store.latestVital(.wristTemperature) {
                    vitalRow(
                        kind: .wristTemperature,
                        value: "\(sample.value.formatted(.number.precision(.fractionLength(1))))°C",
                        detail: "\(sample.source.caveat) Last night."
                    )
                }
            }
        }
    }

    private func vitalRow(kind: VitalsKind, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(kind.displayName)
                    .font(.subheadline)
                Spacer()
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.orange)
                    .monospacedDigit()
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var personalBests: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Personal bests")
                .font(.headline)
            ForEach(store.records.prefix(5), id: \.self) { record in
                if let exercise = store.library.exercise(id: record.exerciseID) {
                    HStack {
                        Text(exercise.name)
                            .font(.subheadline)
                        Spacer()
                        Text(recordText(record))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.orange)
                    }
                }
            }
        }
    }

    private func recordText(_ record: ProgressiveOverloadEngine.PersonalRecord) -> String {
        let value = record.value.formatted(.number.precision(.fractionLength(0...1)))
        switch record.metric {
        case .maxWeight:         return "\(value) kg"
        case .maxReps:           return "\(value) reps"
        case .estimatedOneRepMax: return "\(value) kg est. 1RM"
        }
    }
}
