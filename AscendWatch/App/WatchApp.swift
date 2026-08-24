import SwiftUI
import AscendKit

@main
struct AscendWatchApp: App {
    @StateObject private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
        }
    }
}

struct WatchRootView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        if store.snapshot != nil, store.machine != nil {
            WatchSessionView()
        } else {
            NavigationStack { WatchIdleView() }
        }
    }
}

/// Days-per-week picker, the same single question the phone asks.
struct WatchPlanSetupView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.dismiss) private var dismiss
    @State private var days = 4

    var body: some View {
        VStack(spacing: 8) {
            Text("Days per week")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(days)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .focusable()
                .digitalCrownRotation(
                    Binding(get: { Double(days) }, set: { days = max(2, min(6, Int($0.rounded()))) }),
                    from: 2, through: 6, by: 1, sensitivity: .low
                )

            Button("Create plan") {
                store.createLocalPlan(daysPerWeek: days)
                dismiss()
            }
            .tint(.orange)
        }
        .padding(.horizontal, 6)
        .navigationTitle("New plan")
    }
}

/// Nothing running. The Watch cannot start a workout on its own yet - the phone
/// owns plan generation - so this waits for a session to be pushed across.
struct WatchIdleView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 30))
                .foregroundStyle(.orange)

            Text("No workout running")
                .font(.headline)
                .multilineTextAlignment(.center)

            if store.upcoming.isEmpty {
                Text(store.isReachable
                     ? "Start one on your iPhone, or set up here."
                     : "No plan yet. Set one up here.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // The Watch can build its own plan rather than waiting on a
                // phone it may never see - a gym is where the phone is least
                // likely to be reachable.
                NavigationLink {
                    WatchPlanSetupView()
                } label: {
                    Text("Set up a plan")
                }
                .tint(.orange)

                if store.isReachable {
                    Button("Check iPhone") { store.requestSnapshot() }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                }
            } else {
                // The plan is held on the Watch, so this works with the phone
                // in a locker.
                ForEach(store.upcoming.prefix(2)) { workout in
                    Button {
                        store.startLocally(workout)
                    } label: {
                        VStack(spacing: 1) {
                            Text(workout.snapshot.workoutName)
                                .font(.caption.weight(.semibold))
                            Text("\(workout.snapshot.exercises.count) exercises")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .tint(.orange)
                }
            }
        }
        .padding()
    }
}


