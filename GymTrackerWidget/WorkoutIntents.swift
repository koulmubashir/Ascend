import AppIntents
import Foundation
import GymKit

/// Interactive Live Activity buttons.
///
/// These run in the widget extension, a separate process from the app, so they
/// cannot call into `AppStore` directly. They drop a small instruction into the
/// shared App Group container; the app picks it up and applies it through the
/// same `SessionStateMachine` as a tap in the app would.
///
/// Doing it this way rather than mutating session state here keeps one owner of
/// the workout - the app - and avoids two processes racing to advance the same
/// session.
@available(iOS 17.0, *)
struct SkipRestIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip rest"
    static var description = IntentDescription("End the current rest period early.")

    func perform() async throws -> some IntentResult {
        SharedSessionCommands.write(.skipRest)
        return .result()
    }
}

@available(iOS 17.0, *)
struct LogSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Log set"
    static var description = IntentDescription("Mark the current set as done.")

    func perform() async throws -> some IntentResult {
        SharedSessionCommands.write(.logSet)
        return .result()
    }
}
