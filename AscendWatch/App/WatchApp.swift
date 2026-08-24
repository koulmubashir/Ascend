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
            WatchIdleView()
        }
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
                     ? "Start one on your iPhone."
                     : "iPhone not reachable.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Check again") { store.requestSnapshot() }
                    .font(.caption)
                    .buttonStyle(.bordered)
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


