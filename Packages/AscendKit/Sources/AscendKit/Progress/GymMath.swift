import Foundation

/// Small calculations you would otherwise do in your head between sets.
public enum PlateCalculator {

    /// Plates available per side, heaviest first. Metric gym defaults.
    public static let metricPlates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    public static let standardBarKg: Double = 20

    public struct Loading: Equatable, Sendable {
        /// Plates for one side, heaviest first.
        public var perSide: [Double]
        /// What the bar actually weighs once loaded. Differs from the target
        /// when the plates on hand cannot make it exactly.
        public var achievedTotal: Double
        public var isExact: Bool
        public var barWeight: Double

        public var summary: String {
            guard !perSide.isEmpty else { return "Empty bar" }
            return perSide
                .map { $0.formatted(.number.precision(.fractionLength(0...2))) }
                .joined(separator: " + ")
        }
    }

    /// Greedy from the heaviest plate down, which is how anyone actually loads
    /// a bar. Returns what is achievable rather than failing when the target
    /// cannot be hit exactly.
    public static func plates(
        for target: Double,
        bar: Double = standardBarKg,
        available: [Double] = metricPlates
    ) -> Loading {
        guard target > bar else {
            return Loading(perSide: [], achievedTotal: bar, isExact: target == bar, barWeight: bar)
        }

        var remainingPerSide = (target - bar) / 2
        var chosen: [Double] = []
        for plate in available.sorted(by: >) {
            while remainingPerSide >= plate - 0.0001 {
                chosen.append(plate)
                remainingPerSide -= plate
            }
        }

        let achieved = bar + chosen.reduce(0, +) * 2
        return Loading(
            perSide: chosen,
            achievedTotal: achieved,
            isExact: abs(achieved - target) < 0.0001,
            barWeight: bar
        )
    }
}

public enum WarmupPlanner {

    public struct WarmupSet: Identifiable, Equatable, Sendable {
        public var weight: Double
        public var reps: Int
        public var percentOfWorking: Int

        public var id: Int { Int(weight * 100) &* 1000 &+ reps }

        public init(weight: Double, reps: Int, percentOfWorking: Int = 0) {
            self.weight = weight
            self.reps = reps
            self.percentOfWorking = percentOfWorking
        }
    }

    /// A ramp up to the working weight.
    ///
    /// Percentages are the conventional 40/60/80 ramp with rep counts dropping
    /// as the weight climbs. Light working weights get fewer warm-up sets -
    /// ramping to 30 kg in four steps is a waste of a gym session.
    public static func ramp(
        to workingWeight: Double,
        bar: Double = PlateCalculator.standardBarKg,
        available: [Double] = PlateCalculator.metricPlates
    ) -> [WarmupSet] {
        guard workingWeight > bar else { return [] }

        let steps: [(percent: Double, reps: Int)]
        switch workingWeight {
        case ..<40:  steps = [(0.5, 8)]
        case ..<70:  steps = [(0.4, 8), (0.7, 5)]
        default:     steps = [(0.4, 8), (0.6, 5), (0.8, 3)]
        }

        return steps.compactMap { step -> WarmupSet? in
            let raw = workingWeight * step.percent
            // Snap to something the plates can actually make, otherwise the
            // suggestion is unloadable.
            let loading = PlateCalculator.plates(for: raw, bar: bar, available: available)
            guard loading.achievedTotal > bar - 0.0001, loading.achievedTotal < workingWeight
            else { return nil }
            return WarmupSet(
                weight: loading.achievedTotal,
                reps: step.reps,
                percentOfWorking: Int((loading.achievedTotal / workingWeight * 100).rounded())
            )
        }
        // A ramp that repeats the same weight twice is noise.
        .reduce(into: [WarmupSet]()) { result, set in
            if result.last?.weight != set.weight { result.append(set) }
        }
    }
}
