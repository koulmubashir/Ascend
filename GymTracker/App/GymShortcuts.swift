import AppIntents
import Foundation
import GymKit

/// "Hey Siri, start my workout."
///
/// Reuses the same shared-container mailbox as the Lock Screen buttons rather
/// than reaching into the store: an intent may run while the app is not in the
/// foreground, and having one owner of session state is what keeps the phone,
/// the Watch and the Lock Screen from racing each other.
@available(iOS 16.0, *)
struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start workout"
    static var description = IntentDescription("Start today's scheduled workout.")

    /// Bring the app forward - the session screen is the point of the shortcut.
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        SharedSessionCommands.write(.startWorkout)
        return .result()
    }
}

@available(iOS 16.0, *)
struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log water"
    static var description = IntentDescription("Record a glass of water.")

    @Parameter(title: "Millilitres", default: 250)
    var amount: Int

    func perform() async throws -> some IntentResult {
        SharedSessionCommands.write(.logWater(amount))
        return .result()
    }
}

@available(iOS 16.0, *)
struct GymShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Start my workout in \(.applicationName)",
                "Start today's workout in \(.applicationName)",
                "Begin my \(.applicationName) session"
            ],
            shortTitle: "Start workout",
            systemImageName: "figure.strengthtraining.traditional"
        )
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: [
                "Log water in \(.applicationName)",
                "Add water to \(.applicationName)"
            ],
            shortTitle: "Log water",
            systemImageName: "drop"
        )
    }
}
