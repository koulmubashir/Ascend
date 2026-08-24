import SwiftUI
import GymKit

@main
struct GymTrackerApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onChange(of: scenePhase) { phase in
                    // Lock Screen buttons leave a note for the app rather than
                    // mutating session state from another process.
                    if phase == .active { store.applyPendingWidgetCommand() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
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
