import SwiftUI
import UserNotifications
import GymKit

/// Every optional feature is off until switched on here, and each one asks for
/// its own system permission at the moment it is enabled - never in a batch at
/// first launch.
struct SettingsView: View {
    @EnvironmentObject private var store: WorkoutStore

    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("notificationLeadHours") private var leadHours = 3.0
    @AppStorage("healthKitEnabled") private var healthKitEnabled = false
    @AppStorage("proteinTrackingEnabled") private var proteinEnabled = false
    @AppStorage("waterTrackingEnabled") private var waterEnabled = false

    @State private var permissionDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Workout reminders", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { enabled in
                            if enabled { requestNotifications() } else { cancelReminders() }
                        }

                    if notificationsEnabled {
                        VStack(alignment: .leading) {
                            Text("Remind me \(Int(leadHours))h before")
                                .font(.subheadline)
                            Slider(value: $leadHours, in: 1...12, step: 1)
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("A local notification before each scheduled session, and a nudge if one gets missed.")
                }

                Section {
                    Toggle("Apple Health vitals", isOn: $healthKitEnabled)
                    Toggle("Protein tracking", isOn: $proteinEnabled)
                    Toggle("Water tracking", isOn: $waterEnabled)
                } header: {
                    Text("Optional features")
                } footer: {
                    Text("All off by default. Turning one on asks for that permission only.")
                }

                Section("Plan") {
                    LabeledContent("Days per week", value: "\(store.state.plan?.daysPerWeek ?? 0)")
                    LabeledContent("Sessions logged", value: "\(store.state.sessions.count)")
                }
            }
            .navigationTitle("Settings")
            .alert("Notifications are off", isPresented: $permissionDenied) {
                Button("Open Settings") { openSystemSettings() }
                Button("Not now", role: .cancel) { }
            } message: {
                Text("Turn notifications on for GymTracker in the Settings app to get workout reminders.")
            }
        }
    }

    private func requestNotifications() {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await MainActor.run {
                if !granted {
                    notificationsEnabled = false
                    permissionDenied = true
                }
            }
        }
    }

    private func cancelReminders() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
