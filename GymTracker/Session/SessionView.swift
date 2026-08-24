import SwiftUI
import GymKit

/// The in-workout flow: exercise, rest, next exercise, done.
///
/// The view owns no session logic - it renders whatever `SessionStateMachine`
/// says and forwards user actions back as events. Phase 2 puts the same engine
/// behind a Watch UI.
struct SessionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var reps = 10
    @State private var weight: Double = 20
    @State private var restRemaining = 0
    @State private var timer: Timer?
    @State private var notes = ""
    @FocusState private var notesFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let machine = store.machine {
                    switch machine.state {
                    case .idle:
                        ProgressView()
                    case let .exercising(exerciseIndex, setIndex):
                        exercising(machine: machine, exerciseIndex: exerciseIndex, setIndex: setIndex)
                    case .resting:
                        resting(machine: machine)
                    case let .complete(finished):
                        complete(finished: finished)
                    }
                } else {
                    complete(finished: false)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End") {
                        store.send(.abandon)
                        stopTimer()
                    }
                }
            }
        }
        .onDisappear { stopTimer() }
    }

    // MARK: - Exercising

    private func exercising(machine: SessionStateMachine, exerciseIndex: Int, setIndex: Int) -> some View {
        let planned = machine.exercises[exerciseIndex]

        return ScrollView {
            VStack(spacing: 18) {
                BodyMapView(regions: planned.exercise.regions)
                    .frame(maxHeight: 260)

                VStack(spacing: 4) {
                    Text(planned.exercise.name)
                        .font(.title2.weight(.bold))
                    Text("Set \(setIndex + 1) of \(planned.targetSets)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                RegionChips(regions: planned.exercise.regions)

                HStack(spacing: 24) {
                    stepper(label: "Reps", value: "\(reps)") { reps = max(1, reps + $0) }
                    stepper(label: "kg", value: weight.formatted(.number.precision(.fractionLength(0...1)))) {
                        weight = max(0, weight + Double($0) * 2.5)
                    }
                }

                Button {
                    complete(planned: planned)
                } label: {
                    Text("Set done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.primary, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Color(.systemBackground))
                }
                .padding(.horizontal)
            }
            .padding(20)
        }
        .onAppear { primeInputs(for: planned) }
    }

    private func stepper(label: String, value: String, onChange: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Button { onChange(-1) } label: { Image(systemName: "minus.circle") }
                Text(value)
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 52)
                Button { onChange(1) } label: { Image(systemName: "plus.circle") }
            }
            .font(.title3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    /// Seed the inputs from what the progression engine suggests, so the common
    /// case is one tap.
    private func primeInputs(for planned: PlannedExercise) {
        let suggestion = store.suggestion(for: planned.exercise)
        reps = suggestion.reps
        if let suggested = suggestion.weight { weight = suggested }
    }

    private func complete(planned: PlannedExercise) {
        let effects = store.send(.setCompleted(reps: reps, weightKg: weight > 0 ? weight : nil))
        for effect in effects {
            if case let .startRestTimer(seconds) = effect {
                startTimer(seconds: seconds)
            }
        }
    }

    // MARK: - Resting

    private func resting(machine: SessionStateMachine) -> some View {
        VStack(spacing: 22) {
            Spacer()

            Text("Rest")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(timeString(restRemaining))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()

            if let next = machine.currentExercise {
                Text("Next: \(next.exercise.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                stopTimer()
                store.send(.skipRest)
            } label: {
                Text("Skip rest")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Complete

    private func complete(finished: Bool) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: finished ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                .font(.system(size: 54))
                .foregroundStyle(finished ? .green : .orange)

            Text(finished ? "Workout complete" : "Workout ended early")
                .font(.title2.weight(.bold))

            if !finished {
                Text("The rest has been moved to your next free day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Anything worth remembering?", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($notesFocused)
                    .onSubmit { saveNotes() }
            }
            .padding(.horizontal, 24)

            if !store.lastSessionRecords.isEmpty {
                VStack(spacing: 6) {
                    Label("\(store.lastSessionRecords.count) personal best\(store.lastSessionRecords.count == 1 ? "" : "s")",
                          systemImage: "trophy")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.orange)
                }
                .padding(.top, 6)
            }

            Spacer()

            Button {
                saveNotes()
                store.isSessionPresented = false
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Color(.systemBackground))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Rest timer

    /// A foreground timer only. Backgrounded rest completion is handled by a
    /// scheduled notification in the notifications work, and by the Watch's own
    /// haptic in Phase 2 - iOS will not keep this running while suspended.
    private func startTimer(seconds: Int) {
        restRemaining = seconds
        stopTimer()

        // The Timer only survives while the app is foregrounded, so back it
        // with a notification that fires whether or not we are still running.
        NotificationScheduler.scheduleRestFinished(
            in: seconds,
            nextExercise: store.machine?.currentExercise?.exercise.name,
            enabled: store.settings.notificationsEnabled
        )

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            guard restRemaining > 0 else {
                stopTimer()
                store.send(.restElapsed)
                return
            }
            restRemaining -= 1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        NotificationScheduler.cancelRestFinished()
    }

    /// Notes attach to the session that just finished, which by this point has
    /// already moved from activeSession into history.
    private func saveNotes() {
        notesFocused = false
        guard let id = store.sessions.last?.id else { return }
        store.setNotes(notes, on: id)
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
