import SwiftUI
import GymKit

/// The in-workout screen. Swipe left to log the set, right to go back a page.
///
/// A `TabView` in page style is the idiomatic watchOS swipe, and it means the
/// gesture is handled by the system rather than a custom `DragGesture` that
/// would fight the Digital Crown and the back swipe.
struct WatchSessionView: View {
    @EnvironmentObject private var store: WatchStore
    @State private var reps = 10
    @State private var weight: Double = 20

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
        TabView {
            liftPage
            inputPage
        }
        .tabViewStyle(.page)
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

                Button {
                    // Prefer what the wrist counted, falling back to the target.
                    let counted = store.motion.reps
                    store.completeSet(reps: counted > 0 ? counted : reps,
                                      weightKg: weight > 0 ? weight : nil)
                } label: {
                    Text("Set done")
                        .frame(maxWidth: .infinity)
                }
                .tint(.orange)
            }
        }
        .padding(.horizontal, 4)
    }

    /// Second page rather than crammed onto the first - the Watch screen cannot
    /// carry the map, the name and two steppers at a readable size.
    private var inputPage: some View {
        VStack(spacing: 10) {
            stepper(label: "Reps", value: "\(reps)") { reps = max(1, reps + $0) }
            stepper(label: "kg", value: weight.formatted(.number.precision(.fractionLength(0...1)))) {
                weight = max(0, weight + Double($0) * 2.5)
            }
        }
        .padding(.horizontal, 6)
    }

    private func stepper(label: String, value: String, onChange: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Button { onChange(-1) } label: { Image(systemName: "minus") }
                    .buttonStyle(.bordered)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                Button { onChange(1) } label: { Image(systemName: "plus") }
                    .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
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
        if let suggested = exercise.suggestedWeightKg { weight = suggested }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
