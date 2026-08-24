import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import GymKit

/// Every optional feature in one place, each off by default.
///
/// Nothing is requested at launch. A toggle asks for its own system permission
/// only at the moment it is switched on, and switching it off just stops the
/// app using it.
struct FeaturesSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingResetConfirm = false
    @State private var exporting = false
    @State private var importing = false
    @State private var importMessage: String?
    @State private var showingPermissionAlert = false
    @State private var permissionMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Workout reminders", isOn: notificationsBinding)
                    if store.settings.notificationsEnabled {
                        Picker("Remind me", selection: $store.settings.notificationLeadHours) {
                            Text("1 hour before").tag(1.0)
                            Text("3 hours before").tag(3.0)
                            Text("6 hours before").tag(6.0)
                            Text("The morning of").tag(12.0)
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("A local notification before each scheduled workout, and a nudge if one is missed.")
                }

                Section {
                    Toggle("Apple Health vitals", isOn: healthBinding)
                } header: {
                    Text("Health")
                } footer: {
                    Text("Heart rate is recorded continuously during a workout. Blood oxygen is a periodic spot check, and wrist temperature is measured overnight only — neither is live. Workouts are also saved to Health so they count toward your rings.")
                }

                Section {
                    Toggle("Protein", isOn: $store.settings.proteinTrackingEnabled)
                    if store.settings.proteinTrackingEnabled {
                        Stepper(
                            "Goal \(store.settings.proteinGoal.formatted(.number.precision(.fractionLength(0)))) g",
                            value: $store.settings.proteinGoal, in: 40...400, step: 10
                        )
                    }
                    Toggle("Water", isOn: $store.settings.waterTrackingEnabled)
                    if store.settings.waterTrackingEnabled {
                        Stepper(
                            "Goal \(store.settings.waterGoal.formatted(.number.precision(.fractionLength(0)))) ml",
                            value: $store.settings.waterGoal, in: 500...6000, step: 250
                        )
                    }
                    if store.nutritionEnabled {
                        Picker("Remind me to log", selection: $store.settings.intakeRemindersPerDay) {
                            Text("Never").tag(0)
                            Text("Twice a day").tag(2)
                            Text("4 times a day").tag(4)
                            Text("6 times a day").tag(6)
                        }
                    }
                } header: {
                    Text("Nutrition")
                } footer: {
                    Text("Log intake through the day. Off unless you turn it on.")
                }

                Section {
                    Toggle("Count reps automatically", isOn: $store.settings.repCountingEnabled)
                    Toggle("Deload weeks", isOn: $store.settings.periodization.isEnabled)
                    if store.settings.periodization.isEnabled {
                        Picker("Every", selection: $store.settings.periodization.cycleWeeks) {
                            Text("3 weeks").tag(3)
                            Text("4 weeks").tag(4)
                            Text("6 weeks").tag(6)
                        }
                        if let weeks = store.weeksUntilDeload {
                            LabeledContent(
                                "Next deload",
                                value: weeks == 0 ? "This week" : "In \(weeks) week\(weeks == 1 ? "" : "s")"
                            )
                        }
                    }
                } header: {
                    Text("Training")
                } footer: {
                    Text("Rep counting uses wrist motion during a Watch workout — it counts reps and notices when a set ends, but never guesses which exercise you are doing. Deload weeks back off weight and sets on a fixed cycle; they do not read your recovery.")
                }

                Section {
                    Button {
                        exporting = true
                    } label: {
                        Label("Export backup", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Restore from backup", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        switch store.backUpToCloud() {
                        case .ok:
                            importMessage = "Backed up to iCloud."
                        case .notSignedIn:
                            importMessage = "Sign in to iCloud in Settings first."
                        case let .tooLarge(bytes):
                            importMessage = "Too large for iCloud (\(bytes / 1024) KB)."
                        case let .failed(reason):
                            importMessage = reason
                        }
                    } label: {
                        Label("Back up to iCloud", systemImage: "icloud.and.arrow.up")
                    }
                    Button {
                        switch store.restoreFromCloud() {
                        case let .success(sessions):
                            importMessage = "Restored \(sessions) session\(sessions == 1 ? "" : "s") from iCloud."
                        case let .failed(reason):
                            importMessage = reason
                        }
                    } label: {
                        Label("Restore from iCloud", systemImage: "icloud.and.arrow.down")
                    }
                    if let synced = store.cloud.lastSyncedAt {
                        LabeledContent("Last backup",
                                       value: synced.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let importMessage {
                        Text(importMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("iCloud keeps one backup of everything. It is a backup, not live sync — restoring replaces what is on this phone. Export writes a file you can keep yourself.")
                }

                Section {
                    LabeledContent("Days per week", value: "\(store.plan?.daysPerWeek ?? 0)")
                    LabeledContent("Custom exercises", value: "\(store.customExercises.count)")
                    Button("Start over", role: .destructive) { showingResetConfirm = true }
                } header: {
                    Text("Plan")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: store.settings) { _ in store.save() }
            .fileExporter(
                isPresented: $exporting,
                document: BackupDocument(data: store.exportData() ?? Data()),
                contentType: .json,
                defaultFilename: store.exportFilename
            ) { result in
                if case .failure(let error) = result {
                    importMessage = "Export failed: \(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.json]
            ) { result in
                switch result {
                case let .success(url):
                    guard let data = try? Data(contentsOf: url) else {
                        importMessage = "Could not read that file."
                        return
                    }
                    switch store.importData(data) {
                    case let .success(sessions):
                        importMessage = "Restored \(sessions) session\(sessions == 1 ? "" : "s")."
                    case let .failed(reason):
                        importMessage = reason
                    }
                case let .failure(error):
                    importMessage = error.localizedDescription
                }
            }
            .confirmationDialog(
                "Delete your plan and all workout history?",
                isPresented: $showingResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) { store.reset() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Notifications are off", isPresented: $showingPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Not now", role: .cancel) {}
            } message: {
                Text(permissionMessage)
            }
        }
    }

    /// Asks for Health access the moment the toggle goes on. Reading vitals and
    /// writing workouts are one authorisation sheet, presented by the system.
    private var healthBinding: Binding<Bool> {
        Binding(
            get: { store.settings.healthKitEnabled },
            set: { wantsOn in
                guard wantsOn else {
                    store.settings.healthKitEnabled = false
                    return
                }
                Task {
                    let granted = await store.health.requestAuthorisation()
                    store.settings.healthKitEnabled = granted
                    if !granted {
                        permissionMessage = store.health.lastError
                            ?? "Health access was not granted. You can change this in the Health app under Sharing."
                        showingPermissionAlert = true
                    }
                }
            }
        )
    }

    /// Requests notification permission the moment the toggle goes on, and
    /// flips itself back if the user declines.
    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { store.settings.notificationsEnabled },
            set: { wantsOn in
                guard wantsOn else {
                    store.settings.notificationsEnabled = false
                    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                    return
                }
                Task {
                    let centre = UNUserNotificationCenter.current()
                    // requestAuthorization only prompts once ever. If the user
                    // said no previously it returns false without showing
                    // anything, so send them to Settings instead of silently
                    // flipping the toggle back.
                    let existing = await centre.notificationSettings().authorizationStatus
                    if existing == .denied {
                        permissionMessage = "You previously turned notifications off for GymTracker. Turn them back on in Settings to get workout reminders."
                        showingPermissionAlert = true
                        return
                    }

                    let granted = (try? await centre.requestAuthorization(
                        options: [.alert, .sound, .badge]
                    )) ?? false

                    store.settings.notificationsEnabled = granted
                    if !granted {
                        permissionMessage = "Turn notifications on for GymTracker in Settings to get workout reminders."
                        showingPermissionAlert = true
                    }
                }
            }
        )
    }
}
