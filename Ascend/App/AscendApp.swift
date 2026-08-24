import SwiftUI
import AscendKit

@main
struct AscendApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onChange(of: scenePhase) { phase in
                    // Lock Screen buttons leave a note for the app rather than
                    // mutating session state from another process.
                    if phase == .active {
                        store.applyPendingWidgetCommand()
                        // Health's background delivery is best effort, so also
                        // import on every foreground rather than relying on it.
                        store.startHealthObservation()
                        Task { await store.importFromHealth() }
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var launching = true

    var body: some View {
        ZStack {
            content
            if launching {
                LaunchView { withAnimation(.easeOut(duration: 0.35)) { launching = false } }
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !store.hasOnboarded {
            OnboardingView()
        } else {
            TabView {
                TodayView()
                    .tabItem { Label("Today", systemImage: "figure.strengthtraining.traditional") }
                SummaryView()
                    .tabItem { Label("Week", systemImage: "chart.bar") }
                if store.nutritionEnabled {
                    NutritionView()
                        .tabItem { Label("Intake", systemImage: "drop") }
                }
                HistoryView()
                    .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                FeaturesSettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        }
    }
}
