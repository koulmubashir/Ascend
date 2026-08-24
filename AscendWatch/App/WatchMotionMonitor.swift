import Foundation
import CoreMotion
import AscendKit

/// Feeds wrist motion into `RepCounter`.
///
/// Only the plumbing lives here - the counting logic is in AscendKit and unit
/// tested against synthetic signals, because you cannot unit test a wrist.
///
/// Uses `userAcceleration` rather than raw accelerometer output, so gravity is
/// already removed and holding the arm at a different angle does not read as
/// movement.
@MainActor
final class WatchMotionMonitor: ObservableObject {

    @Published private(set) var reps = 0
    @Published private(set) var isRunning = false
    /// Set when motion has been quiet long enough that the set looks over.
    @Published private(set) var setLooksFinished = false

    private let motion = CMMotionManager()
    private var counter = RepCounter()
    /// 25Hz, not 50. Reps happen at roughly 0.5-3Hz, so 25 samples a second is
    /// well above what counting needs and halves the wake-ups the motion
    /// coprocessor causes. Battery on a Watch is the scarcest thing there is.
    private let sampleRate: Double = 25

    static var isAvailable: Bool { CMMotionManager().isDeviceMotionAvailable }

    func start() {
        guard motion.isDeviceMotionAvailable, !isRunning else { return }

        counter = RepCounter(configuration: .init(sampleRate: sampleRate))
        reps = 0
        setLooksFinished = false
        isRunning = true

        motion.deviceMotionUpdateInterval = 1 / sampleRate
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.userAcceleration
            let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)

            if let event = self.counter.add(magnitude) {
                switch event {
                case let .rep(count):
                    self.reps = count
                case .setFinished:
                    self.setLooksFinished = true
                }
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        isRunning = false
    }

    /// Suspends sampling during rest. Nothing worth counting happens between
    /// sets, and rest is often the longer half of a session.
    func pause() {
        guard isRunning else { return }
        motion.stopDeviceMotionUpdates()
        isRunning = false
    }

    /// Called when the user logs a set, so counting restarts for the next one.
    func resetForNextSet() {
        counter.reset()
        reps = 0
        setLooksFinished = false
    }
}
