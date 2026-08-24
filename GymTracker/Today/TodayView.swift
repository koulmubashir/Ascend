import SwiftUI
import GymKit

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editingWorkout: ScheduledWorkout?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let workout = store.nextWorkout {
                    content(for: workout)
                } else {
                    allDone
                }
            }
            .navigationTitle("Today")
            .fullScreenCover(isPresented: $store.isSessionPresented) {
                SessionView()
            }
            .sheet(item: $editingWorkout) { workout in
                PlanEditorView(workout: workout)
            }
        }
    }

    @ViewBuilder
    private func content(for workout: ScheduledWorkout) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            header(for: workout)

            BodyMapView(regions: workout.trainingDay.regions)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

            RegionChips(regions: workout.trainingDay.regions)

            Button {
                store.startSession(for: workout)
            } label: {
                Text("Start workout")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Color(.systemBackground))
            }

            exerciseList(for: workout)
            weekStrip
        }
        .padding(20)
    }

    private func header(for workout: ScheduledWorkout) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dayLabel(for: workout))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(workout.trainingDay.name)
                    .font(.largeTitle.weight(.bold))
            }
            Spacer()
            Button {
                editingWorkout = workout
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
            }
            .accessibilityLabel("Edit this day")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exerciseList(for workout: ScheduledWorkout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exercises")
                .font(.headline)

            ForEach(workout.trainingDay.plannedExercises) { planned in
                NavigationLink {
                    ExerciseDetailView(planned: planned, workout: workout)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(planned.exercise.name)
                                .font(.body.weight(.medium))
                            Text("\(planned.targetSets) x \(planned.targetReps)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        suggestionLabel(for: planned.exercise)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func suggestionLabel(for exercise: Exercise) -> some View {
        let suggestion = store.suggestion(for: exercise)
        if let weight = suggestion.weight {
            Text("\(weight, specifier: "%.1f") kg")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.orange)
        }
    }

    private var weekStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This week")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(store.thisWeek) { workout in
                    Circle()
                        .fill(color(for: workout.status))
                        .frame(width: 11, height: 11)
                }
                Spacer()
                Text("\(store.plan?.daysPerWeek ?? 0) days a week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var allDone: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 42))
                .foregroundStyle(.green)
            Text("Nothing scheduled")
                .font(.title3.weight(.semibold))
            Text("Every workout on the plan is done.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 80)
    }

    private func color(for status: ScheduledWorkoutStatus) -> Color {
        switch status {
        case .completed:          return .green
        case .partiallyCompleted: return .orange
        case .missed:             return .red.opacity(0.5)
        case .rescheduled:        return .blue.opacity(0.5)
        case .upcoming:           return .secondary.opacity(0.25)
        }
    }

    private func dayLabel(for workout: ScheduledWorkout) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(workout.scheduledDate) { return "Today" }
        if cal.isDateInTomorrow(workout.scheduledDate) { return "Tomorrow" }
        return workout.scheduledDate.formatted(.dateTime.weekday(.wide).month().day())
    }
}

/// Exercise detail with the progression hint and substitution options.
struct ExerciseDetailView: View {
    @EnvironmentObject private var store: AppStore
    let planned: PlannedExercise
    let workout: ScheduledWorkout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BodyMapView(regions: planned.exercise.regions)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                RegionChips(regions: planned.exercise.regions)

                let suggestion = store.suggestion(for: planned.exercise)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next session")
                        .font(.headline)
                    Text(suggestionText(suggestion))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                let suggestedWeight = suggestion.weight ?? 0
                if suggestedWeight > PlateCalculator.standardBarKg {
                    let loading = PlateCalculator.plates(for: suggestedWeight)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Plates per side")
                            .font(.headline)
                        Text(loading.summary)
                            .font(.subheadline)
                            .foregroundStyle(Color.orange)
                        if !loading.isExact {
                            Text("Closest loadable: \(loading.achievedTotal.formatted(.number.precision(.fractionLength(0...1)))) kg")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    let ramp = WarmupPlanner.ramp(to: suggestedWeight)
                    if !ramp.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Warm-up")
                                .font(.headline)
                            ForEach(ramp) { set in
                                HStack {
                                    Text("\(set.weight.formatted(.number.precision(.fractionLength(0...1)))) kg x \(set.reps)")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(set.percentOfWorking)%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                NavigationLink {
                    ExerciseHistoryView(exercise: planned.exercise)
                } label: {
                    HStack {
                        Label("History and progress", systemImage: "chart.line.uptrend.xyaxis")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                let alternates = store.library.alternates(for: planned.exercise)
                if !alternates.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Swap for")
                            .font(.headline)
                        ForEach(alternates) { alternate in
                            Button {
                                store.swap(planned, to: alternate, in: workout)
                            } label: {
                                HStack {
                                    Text(alternate.name)
                                    Spacer()
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(.caption)
                                }
                                .padding(12)
                                .background(Color.secondary.opacity(0.07),
                                            in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(planned.exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func suggestionText(_ suggestion: ProgressiveOverloadEngine.Suggestion) -> String {
        let target = suggestion.weight.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) kg x \(suggestion.reps)" }
            ?? "\(suggestion.reps) reps"
        switch suggestion.rationale {
        case .noHistory:  return "\(target) — no history yet, start here."
        case .addWeight:  return "\(target) — you hit every target rep last time."
        case .addReps:    return "\(target) — build reps before adding weight."
        case .holdSteady: return "\(target) — hold here until it feels solid."
        }
    }
}
