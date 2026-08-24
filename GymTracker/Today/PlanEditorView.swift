import SwiftUI
import GymKit

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
    private var current: ScheduledWorkout? {
        store.schedule.first { $0.id == workout.id }
    }

    var body: some View {
        NavigationStack {
            List {
                if let day = current?.trainingDay {
                    Section {
                        ForEach(day.plannedExercises.sorted(by: { $0.orderIndex < $1.orderIndex })) { planned in
                            NavigationLink {
                                TargetEditorView(planned: planned, workout: workout)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(planned.exercise.name)
                                    Text("\(planned.targetSets) x \(planned.targetReps) · \(planned.restSeconds)s rest")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                        Text("Drag to reorder. Swipe to remove.")
                    }

                    Section {
                        Button {
                            showingPicker = true
                        } label: {
                            Label("Add exercise", systemImage: "plus")
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(current?.trainingDay.name ?? "Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
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
