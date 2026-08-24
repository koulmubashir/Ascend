import Foundation
import WatchConnectivity
import AscendKit

/// Phone side of the Watch link.
///
/// Ownership split: the phone owns plan generation and history, the Watch owns
/// a session once it is running there. So this pushes a snapshot when a workout
/// starts and otherwise mostly listens, folding the Watch's logs back into the
/// store.
@MainActor
final class PhoneSessionManager: NSObject, ObservableObject {

    @Published private(set) var isWatchReachable = false

    /// Set by AppStore so incoming Watch messages can be applied.
    weak var store: AppStore?

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    override init() {
        super.init()
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Sending

    func sendSessionStart(_ snapshot: WatchSync.SessionSnapshot) {
        send(.startSession(snapshot))
    }

    func sendNoActiveSession() {
        send(.noActiveSession)
    }

    /// Pushes the upcoming plan so the Watch can start a workout alone.
    /// Uses applicationContext semantics via transferUserInfo so it survives
    /// the Watch being asleep.
    func sendPlan(_ plan: WatchSync.PlanSnapshot) {
        send(.planUpdated(plan))
    }

    private func send(_ message: WatchSync.Message) {
        guard let session, session.activationState == .activated,
              let payload = try? WatchSync.dictionary(for: message)
        else { return }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }
}

extension PhoneSessionManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.isWatchReachable = session.isReachable }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isWatchReachable = session.isReachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }

    // Required on iOS so the session can be handed to a newly paired Watch.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    private nonisolated func handle(_ dictionary: [String: Any]) {
        guard let message = try? WatchSync.message(from: dictionary) else { return }
        Task { @MainActor in
            switch message {
            case let .setCompleted(log):
                self.store?.applyWatchSet(log)
            case let .sessionEnded(payload):
                self.store?.applyWatchSessionEnd(payload)
            case .requestSnapshot:
                if let snapshot = self.store?.currentWatchSnapshot() {
                    self.sendSessionStart(snapshot)
                } else {
                    self.sendNoActiveSession()
                }
            case let .watchStartedSession(sessionID, workoutID):
                self.store?.adoptWatchSession(sessionID: sessionID, workoutID: workoutID)
            case .startSession, .noActiveSession, .planUpdated:
                // Watch-bound messages; nothing for the phone to do.
                break
            }
        }
    }
}
