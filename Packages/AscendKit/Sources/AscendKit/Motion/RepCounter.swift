import Foundation

/// Counts reps from wrist motion, and notices when a set has finished.
///
/// Deliberately signal processing rather than machine learning. Counting
/// repetitions in a periodic signal is a solved problem that needs no training
/// data; identifying *which* exercise you are doing from one wrist is not, and
/// the app already knows which exercise is planned. So this counts and detects
/// rest, and never guesses at the movement.
///
/// Feed it a magnitude per motion sample - typically the length of the user
/// acceleration vector. Sample rate is assumed roughly constant.
public struct RepCounter {

    public struct Configuration: Equatable, Sendable {
        /// Samples per second the caller is feeding in.
        public var sampleRate: Double
        /// A rep must clear this much acceleration to count, which filters out
        /// fidgeting and the watch face being tapped.
        public var minimumAmplitude: Double
        /// Fastest plausible rep. Anything quicker is noise, not a repetition.
        public var minimumRepSeconds: Double
        /// Slowest plausible rep before we assume the set has stopped.
        public var maximumRepSeconds: Double
        /// Quiet time before the set is considered over.
        public var restAfterSeconds: Double
        /// Window used for the moving baseline, in seconds. Wants to span
        /// several reps so the quiet troughs between them are represented.
        public var baselineSeconds: Double

        public init(
            sampleRate: Double = 50,
            minimumAmplitude: Double = 0.18,
            minimumRepSeconds: Double = 0.6,
            maximumRepSeconds: Double = 8,
            restAfterSeconds: Double = 5,
            baselineSeconds: Double = 4
        ) {
            self.sampleRate = max(1, sampleRate)
            self.minimumAmplitude = max(0, minimumAmplitude)
            self.minimumRepSeconds = max(0.1, minimumRepSeconds)
            self.maximumRepSeconds = max(minimumRepSeconds, maximumRepSeconds)
            self.restAfterSeconds = max(1, restAfterSeconds)
            self.baselineSeconds = max(0.5, baselineSeconds)
        }
    }

    public enum Event: Equatable, Sendable {
        case rep(count: Int)
        /// Motion stopped for long enough that the set looks finished.
        case setFinished(reps: Int)
    }

    public private(set) var reps = 0

    private let config: Configuration
    private var samples: [Double] = []
    private var elapsed: Double = 0
    private var lastRepAt: Double = -.greatestFiniteMagnitude
    private var lastMotionAt: Double = 0
    private var isAboveBaseline = false
    private var peakSinceCrossing: Double = 0
    private var hasFinished = false

    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
    }

    /// Feeds one motion magnitude. Returns any event it triggered.
    ///
    /// Counting happens on the *falling* edge rather than the peak: a rep is
    /// only confirmed once the movement comes back down, which avoids counting
    /// a single slow press as several reps as the signal wobbles near its top.
    public mutating func add(_ magnitude: Double) -> Event? {
        guard !hasFinished else { return nil }

        elapsed += 1 / config.sampleRate
        samples.append(magnitude)

        let window = Int(config.baselineSeconds * config.sampleRate)
        if samples.count > window { samples.removeFirst(samples.count - window) }

        // A low percentile, not a mean or a median. During a set the signal is
        // above rest for most of every rep, so a median tracks the movement
        // itself and the threshold can never be crossed. The 20th percentile
        // picks out the quiet troughs between reps, which is what "at rest"
        // actually looks like - and being a percentile it still ignores one
        // violent spike from racking the bar.
        let baseline = percentile(samples, 0.2)
        let threshold = baseline + config.minimumAmplitude

        if magnitude > threshold {
            lastMotionAt = elapsed
            isAboveBaseline = true
            peakSinceCrossing = max(peakSinceCrossing, magnitude)
            return nil
        }

        // Falling back through the threshold completes a rep.
        if isAboveBaseline {
            isAboveBaseline = false
            let sinceLast = elapsed - lastRepAt
            let cleared = peakSinceCrossing - baseline >= config.minimumAmplitude
            peakSinceCrossing = 0

            if cleared, sinceLast >= config.minimumRepSeconds {
                reps += 1
                lastRepAt = elapsed
                return .rep(count: reps)
            }
            return nil
        }

        if reps > 0, elapsed - lastMotionAt >= config.restAfterSeconds {
            hasFinished = true
            return .setFinished(reps: reps)
        }
        return nil
    }

    /// Whether the set has been declared finished.
    public var isFinished: Bool { hasFinished }

    public mutating func reset() {
        reps = 0
        samples = []
        elapsed = 0
        lastRepAt = -.greatestFiniteMagnitude
        lastMotionAt = 0
        isAboveBaseline = false
        peakSinceCrossing = 0
        hasFinished = false
    }

    private func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[min(max(0, index), sorted.count - 1)]
    }
}
