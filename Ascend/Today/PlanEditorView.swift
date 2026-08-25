import SwiftUI
import AscendKit

/// Editing a training day: reorder, add, remove, retarget, rename.
struct PlanEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let workout: ScheduledWorkout

    @State private var showingPicker = false
    @State private var renaming = false
    @State private var draftName = ""

    /// Re-read from the store so edits show immediately rather than against the
    /// copy this view was handed.
    private func ordered(_ day: TrainingDay) -> [PlannedExercise] {
        day.plannedExercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// True when this exercise runs straight after the one above it with no
    /// rest between - which is what makes the pair a superset.
    private func isJoinedToPrevious(_ planned: PlannedExercise, in day: TrainingDay) -> Bool {
        let list = ordered(day)
        guard let tag = planned.supersetTag,
              let index = list.firstIndex(where: { $0.id == planned.id }),
              index > 0
        else { return false }
        return list[index - 1].supersetTag == tag
    }

    private func detail(for planned: PlannedExercise, in day: TrainingDay) -> String {
        let base = "\(planned.targetSets) x \(planned.targetReps)"
        return isJoinedToPrevious(planned, in: day)
            ? "\(base) · no rest, superset"
            : "\(base) · \(planned.restSeconds)s rest"
    }

    private var current: ScheduledWorkout? {
        store.schedule.first { $0.id == workout.id }
    }

    var body: some View {
        NavigationStack {
            List {
                if let day = current?.trainingDay {
                    Section {
                        ForEach(ordered(day)) { planned in
                            NavigationLink {
                                TargetEditorView(planned: planned, workout: workout)
                            } label: {
                                HStack(spacing: 10) {
                                    if isJoinedToPrevious(planned, in: day) {
                                        Image(systemName: "link")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .accessibilityLabel("Supersetted with the exercise above")
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(planned.exercise.name)
                                        Text(detail(for: planned, in: day))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            let ordered = day.plannedExercises.sorted { $0.orderIndex < $1.orderIndex }
                            for index in offsets {
                                store.removeExercise(ordered[index], from: workout)
                            }
                        }
                        .onMove { from, to in
                            store.moveExercises(in: workout, from: from, to: to)
                        }
                    } header: {
                        Text("Exercises")
                    } footer: {
                        Text("Drag to reorder. Swipe to remove. Tap an exercise to set targets or superset it with the one above.")
                    }

                    Section {
                        Button {
                            showingPicker = true
                        } label: {
                            Label("Add exercise", systemImage: "plus")
                        }
                    }

                    Section {
                        Picker("Changes apply to", selection: $store.editScope) {
                            Text("Every \(day.name) day").tag(PlanEditor.Scope.series)
                            Text("Only this one").tag(PlanEditor.Scope.thisDayOnly)
                        }
                        .pickerStyle(.inline)
                    } footer: {
                        Text(store.editScope == .series
                             ? "Updates your plan and every future \(day.name) day. Workouts you have already done are left as they were."
                             : "Changes only the session on this date.")
                    }
                }
            }
            // Not pinned to .active: an always-on edit mode swallows taps on
            // the rows, which left the per-exercise editor unreachable. Reorder
            // is behind the Edit button instead; delete still works by swipe.
            .navigationTitle(current?.trainingDay.name ?? "Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Rename") {
                        draftName = current?.trainingDay.name ?? ""
                        renaming = true
                    }
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView(workout: workout)
            }
            .alert("Rename day", isPresented: $renaming) {
                TextField("Name", text: $draftName)
                Button("Save") { store.renameDay(workout, to: draftName) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

/// Sets, reps and rest for one planned exercise.
struct TargetEditorView: View {
    @EnvironmentObject private var store: AppStore
    let planned: PlannedExercise
    let workout: ScheduledWorkout

    private var current: PlannedExercise {
        store.schedule
            .first { $0.id == workout.id }?
            .trainingDay.plannedExercises
            .first { $0.id == planned.id } ?? planned
    }

    private var ordered: [PlannedExercise] {
        (store.schedule.first { $0.id == workout.id }?.trainingDay.plannedExercises ?? [])
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    /// A superset is a run of neighbours, so only the exercise directly above
    /// can be joined to.
    private var exerciseAbove: PlannedExercise? {
        guard let index = ordered.firstIndex(where: { $0.id == planned.id }), index > 0
        else { return nil }
        return ordered[index - 1]
    }

    private var isSupersetted: Bool {
        guard let tag = current.supersetTag, let above = exerciseAbove else { return false }
        return above.supersetTag == tag
    }

    var body: some View {
        Form {
            Section {
                Stepper("Sets: \(current.targetSets)", value: Binding(
                    get: { current.targetSets },
                    set: { store.updateTargets(planned, in: workout, sets: $0) }
                ), in: 1...10)

                Stepper("Reps: \(current.targetReps)", value: Binding(
                    get: { current.targetReps },
                    set: { store.updateTargets(planned, in: workout, reps: $0) }
                ), in: 1...50)

                Stepper("Rest: \(current.restSeconds)s", value: Binding(
                    get: { current.restSeconds },
                    set: { store.updateTargets(planned, in: workout, rest: $0) }
                ), in: 0...300, step: 15)
            } header: {
                Text("Targets")
            }

            if let above = exerciseAbove {
                Section {
                    Toggle("Superset with \(above.exercise.name)", isOn: Binding(
                        get: { isSupersetted },
                        set: { _ in store.toggleSuperset(planned, in: workout) }
                    ))
                } footer: {
                    Text(isSupersetted
                         ? "Run back to back with \(above.exercise.name), resting only once the round is done."
                         : "Run this straight after \(above.exercise.name) with no rest between.")
                }
            }

            Section {
                RegionChips(regions: planned.exercise.regions)
            } header: {
                Text("Trains")
            }
        }
        .navigationTitle(planned.exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Pick from the library, or create your own.
struct ExercisePickerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let workout: ScheduledWorkout

    @State private var search = ""
    @State private var creating = false

    private var results: [Exercise] {
        let all = store.allExercises
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        creating = true
                    } label: {
                        Label("Create new exercise", systemImage: "plus.circle")
                    }
                }

                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    let inGroup = results.filter { $0.group == group }
                    if !inGroup.isEmpty {
                        Section(group.displayName) {
                            ForEach(inGroup) { exercise in
                                Button {
                                    store.addExercise(exercise, to: workout)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(exercise.name)
                                            .foregroundStyle(.primary)
                                        Text("\(exercise.defaultSets) x \(exercise.defaultReps)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $creating) {
                CustomExerciseView { exercise in
                    store.addExercise(exercise, to: workout)
                    dismiss()
                }
            }
        }
    }
}

struct CustomExerciseView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var onCreate: (Exercise) -> Void

    @State private var name = ""
    @State private var group: MuscleGroup = .chest
    @State private var regions: Set<MuscleRegion> = []
    @State private var sets = 3
    @State private var reps = 10
    @State private var rest = 90
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Group", selection: $group) {
                        ForEach(MuscleGroup.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Stepper("Sets: \(sets)", value: $sets, in: 1...10)
                    Stepper("Reps: \(reps)", value: $reps, in: 1...50)
                    Stepper("Rest: \(rest)s", value: $rest, in: 0...300, step: 15)
                }

                Section {
                    ForEach(MuscleRegion.allCases, id: \.self) { region in
                        Button {
                            if regions.contains(region) { regions.remove(region) } else { regions.insert(region) }
                        } label: {
                            HStack {
                                Text(region.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if regions.contains(region) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Muscles trained")
                } footer: {
                    Text("Leave empty to use the group's defaults. This drives which body map is shown.")
                }
            }
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { submit() }
                }
            }
        }
    }

    private func submit() {
        guard let exercise = store.addCustomExercise(
            name: name, group: group, regions: regions,
            sets: sets, reps: reps, rest: rest
        ) else {
            error = "Give the exercise a name."
            return
        }
        onCreate(exercise)
        dismiss()
    }
}
