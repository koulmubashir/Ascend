import SwiftUI
import AscendKit

/// The in-workout screen. Swipe left or right to log the set and start resting.
///
/// One page rather than a paged `TabView`: paging consumed the horizontal
/// gesture, and logging a set by swiping is the whole point of running this on
/// a wrist. Reps go on the Digital Crown, which frees the swipe entirely.
///
/// The button stays. A swipe is not discoverable and is unusable with
/// VoiceOver, so it is an accelerator rather than the only way through.
struct WatchSessionView: View {
    @EnvironmentObject private var store: WatchStore
    @State private var reps = 10
    @State private var weight: Double = 20
    @State private var crownReps: Double = 10

    var body: some View {
        Group {
            if let machine = store.machine {
                switch machine.state {
                case .idle:
                    ProgressView()
                case .exercising:
                    exercising
                case .resting:
                    resting
                case let .complete(finished):
                    complete(finished: finished)
                }
            }
        }
        .onChange(of: store.currentExercise?.id) { _ in prime() }
        .onAppear { prime() }
    }

    // MARK: - Exercising

    private var exercising: some View {
        liftPage
            .focusable()
            .digitalCrownRotation(
                $crownReps,
                from: 1, through: 50, by: 1,
                sensitivity: .low,
                isContinuous: false
            )
            .onChange(of: crownReps) { value in
                reps = max(1, Int(value.rounded()))
            }
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        // Either direction logs the set - asking someone to
                        // remember which way costs more than it saves.
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        logSet()
                    }
            )
    }

    private func logSet() {
        let counted = store.motion.reps
        store.completeSet(reps: counted > 0 ? counted : reps,
                          weightKg: weight > 0 ? weight : nil)
    }

    private var liftPage: some View {
        VStack(spacing: 4) {
            if let exercise = store.currentExercise {
                WatchBodyMapView(regions: exercise.regions)
                    .frame(maxHeight: 74)

                Text(exercise.name)
                    .font(.headline)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                HStack(spacing: 6) {
                    Text("Set \(store.currentSetNumber) of \(exercise.targetSets)")
                    if let bpm = store.workout.currentHeartRate {
                        Label("\(bpm)", systemImage: "heart.fill")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if store.motion.isRunning {
                    Text(store.motion.setLooksFinished
                         ? "\(store.motion.reps) reps — set looks done"
                         : "\(store.motion.reps) reps counted")
                        .font(.caption2)
                        .foregroundStyle(store.motion.setLooksFinished ? Color.orange : .secondary)
                }

                HStack(spacing: 6) {
                    Button {
                        weight = max(0, weight - 2.5)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.bordered)

                    Text("\(reps) x \(weight.formatted(.number.precision(.fractionLength(0...1))))kg")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)

                    Button {
                        weight += 2.5
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: logSet) {
                    Text("Set done")
                        .frame(maxWidth: .infinity)
                }
                .tint(.orange)
                .accessibilityHint("Or swipe left or right")
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Resting

    private var resting: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("Rest")
                if let bpm = store.workout.currentHeartRate {
                    Label("\(bpm)", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(timeString(store.restRemaining))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            if let next = store.currentExercise {
                Text(next.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button("Skip") { store.skipRest() }
                .buttonStyle(.bordered)
                .font(.caption)
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Complete

    private func complete(finished: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: finished ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(finished ? .green : .orange)

            Text(finished ? "Done" : "Ended early")
                .font(.headline)

            if !store.isReachable {
                Text("Will sync when your iPhone is back in range.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Close") { store.clear() }
                .buttonStyle(.bordered)
                .font(.caption)
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Helpers

    private func prime() {
        guard let exercise = store.currentExercise else { return }
        reps = exercise.targetReps
        crownReps = Double(exercise.targetReps)
        if let suggested = exercise.suggestedWeightKg { weight = suggested }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
