import SwiftUI
import GymKit

struct TodayView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var activeWorkout: ScheduledWorkout?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let workout = store.todaysWorkout ?? store.nextWorkout {
                        header(for: workout)
                        MuscleBodyMapView(
                            key: workout.trainingDay.bodyMapKey,
                            groups: workout.trainingDay.groups
                        )
                        groupTags(workout.trainingDay.groups)
                        exerciseList(workout)
                        startButton(workout)
                    } else {
                        restDay
                    }
                }
                .padding(20)
            }
            .navigationTitle("Today")
            .fullScreenCover(item: $activeWorkout) { workout in
                SessionView(workout: workout)
            }
        }
    }

    // MARK: - Pieces

    private func header(for workout: ScheduledWorkout) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayLabel(for: workout))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(workout.trainingDay.name)
                    .font(.title.weight(.semibold))
            }
            Spacer()
            if store.streak > 0 {
                Label("\(store.streak) day streak", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
    }

    private func groupTags(_ groups: [MuscleGroup]) -> some View {
        HStack(spacing: 7) {
            ForEach(groups, id: \.self) { group in
                Text(group.displayName)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.14), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
    }

    private func exerciseList(_ workout: ScheduledWorkout) -> some View {
        VStack(spacing: 0) {
            ForEach(workout.trainingDay.plannedExercises.sorted { $0.orderIndex < $1.orderIndex }) { planned in
                if let exercise = store.exercise(id: planned.exerciseID) {
                    ExerciseRow(
                        exercise: exercise,
                        planned: planned,
                        suggestion: store.suggestion(for: exercise),
                        alternates: store.library.alternates(for: exercise),
                        onSubstitute: { store.substitute(planned, with: $0, in: workout) }
                    )
                    Divider()
                }
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func startButton(_ workout: ScheduledWorkout) -> some View {
        Button {
            activeWorkout = workout
        } label: {
            Text("Start workout")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(workout.trainingDay.plannedExercises.isEmpty)
    }

    private var restDay: some View {
        VStack(spacing: 12) {
            MuscleBodyMapView(key: .rest)
            Text("Rest day")
                .font(.title2.weight(.semibold))
            Text("Nothing scheduled. Recovery is part of the plan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func dayLabel(for workout: ScheduledWorkout) -> String {
        if Calendar.current.isDateInToday(workout.scheduledDate) {
            return workout.trainingDay.isMakeupDay ? "Today · makeup session" : "Today"
        }
        return workout.scheduledDate.formatted(.dateTime.weekday(.wide).month().day())
    }
}

// MARK: - Row

private struct ExerciseRow: View {
    let exercise: Exercise
    let planned: PlannedExercise
    let suggestion: ProgressiveOverloadEngine.Suggestion
    let alternates: [Exercise]
    let onSubstitute: (Exercise) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.body.weight(.medium))
                Text("\(planned.targetSets) × \(planned.targetReps)\(suggestionSuffix)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !alternates.isEmpty {
                Menu {
                    ForEach(alternates) { alt in
                        Button(alt.name) { onSubstitute(alt) }
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Swap \(exercise.name)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var suggestionSuffix: String {
        guard let weight = suggestion.weight else { return "" }
        let formatted = weight.formatted(.number.precision(.fractionLength(0...1)))
        switch suggestion.rationale {
        case .addWeight: return "  ·  try \(formatted) kg"
        case .addReps:   return "  ·  \(formatted) kg, push the reps"
        case .holdSteady: return "  ·  hold \(formatted) kg"
        case .noHistory: return ""
        }
    }
}
