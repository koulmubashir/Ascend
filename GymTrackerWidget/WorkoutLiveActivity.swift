import ActivityKit
import SwiftUI
import WidgetKit
import GymKit

/// Lock Screen and Dynamic Island presentation for a running workout.
///
/// The rest countdown uses `Text(timerInterval:)`, which the system ticks
/// itself. That is deliberate: iOS budgets how often an activity may be
/// updated, so driving a per-second countdown with `Activity.update` would be
/// throttled and end up frozen. The app pushes one update per real state
/// change and lets the clock run on its own.
@available(iOS 16.1, *)
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.info.workoutName, systemImage: "figure.strengthtraining.traditional")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.exerciseNumber)/\(context.state.totalExercises)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.exerciseName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    bottomControls(context)
                }
            } compactLeading: {
                Image(systemName: context.state.phase == .resting ? "timer" : "dumbbell.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                if context.state.phase == .resting, let end = context.state.restEndsAt {
                    Text(timerInterval: Date()...end, countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                } else {
                    Text(context.state.compactSummary)
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: context.state.phase == .resting ? "timer" : "dumbbell.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(context.attributes.info.workoutName, systemImage: "figure.strengthtraining.traditional")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                Spacer()
                Text("Exercise \(context.state.exerciseNumber) of \(context.state.totalExercises)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.exerciseName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("Set \(context.state.setNumber) of \(context.state.totalSets)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if context.state.phase == .resting, let end = context.state.restEndsAt {
                    Text(timerInterval: Date()...end, countsDown: true)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }

            ProgressView(value: context.state.progress)
                .tint(.orange)

            bottomControls(context)
        }
        .padding(14)
    }

    /// Interactive buttons need App Intents, which are iOS 17+. On 16.x the
    /// activity still renders - it is just informational, which is a reasonable
    /// degradation rather than hiding the whole thing.
    @ViewBuilder
    private func bottomControls(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        if #available(iOS 17.0, *) {
            HStack(spacing: 8) {
                if context.state.phase == .resting {
                    Button(intent: SkipRestIntent()) {
                        Label("Skip rest", systemImage: "forward.fill")
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.orange)
                } else {
                    Button(intent: LogSetIntent()) {
                        Label("Set done", systemImage: "checkmark")
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.orange)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
