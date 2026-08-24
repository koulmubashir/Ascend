import SwiftUI
import Charts
import AscendKit

/// Every session for one exercise, and whether it is going anywhere.
struct ExerciseHistoryView: View {
    @EnvironmentObject private var store: AppStore
    let exercise: Exercise

    private var points: [ProgressStats.SessionPoint] { store.history(for: exercise) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if points.isEmpty {
                    empty
                } else {
                    headline
                    weightChart
                    volumeChart
                    sessionList
                }
            }
            .padding(20)
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No history yet")
                .font(.title3.weight(.semibold))
            Text("Log a set of \(exercise.name) and it will show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var headline: some View {
        HStack(spacing: 12) {
            tile(label: "Sessions", value: "\(points.count)")
            if let heaviest = points.compactMap(\.topSetWeight).max() {
                tile(label: "Best set", value: "\(fmt(heaviest)) kg")
            }
            if let trend = store.trend(for: exercise) {
                tile(
                    label: "Change",
                    value: "\(trend > 0 ? "+" : "")\(fmt(trend))%",
                    tint: trend > 0 ? .green : (trend < 0 ? .red : .secondary)
                )
            }
        }
    }

    private func tile(label: String, value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Only plotted when there is weight to plot - a bodyweight exercise would
    /// otherwise show a flat line at zero, which says nothing.
    @ViewBuilder
    private var weightChart: some View {
        let weighted = points.filter { $0.topSetWeight != nil }
        if weighted.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Top set")
                    .font(.headline)
                Chart(weighted) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("kg", point.topSetWeight ?? 0)
                    )
                    .foregroundStyle(Color.orange)
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("kg", point.topSetWeight ?? 0)
                    )
                    .foregroundStyle(Color.orange)
                }
                .chartYAxisLabel("kg")
                .frame(height: 180)
            }
        }
    }

    @ViewBuilder
    private var volumeChart: some View {
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Volume per session")
                    .font(.headline)
                Chart(points) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("kg", point.totalVolume)
                    )
                    .foregroundStyle(Color.orange.opacity(0.7))
                }
                .frame(height: 140)
            }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sessions")
                .font(.headline)
            ForEach(points.reversed()) { point in
                HStack {
                    Text(point.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                    Spacer()
                    Text(detail(point))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func detail(_ point: ProgressStats.SessionPoint) -> String {
        var parts = ["\(point.setCount) set\(point.setCount == 1 ? "" : "s")"]
        if let weight = point.topSetWeight {
            parts.append("top \(fmt(weight)) kg")
        }
        if point.totalVolume > 0 {
            parts.append("\(fmt(point.totalVolume)) kg total")
        }
        return parts.joined(separator: " · ")
    }

    private func fmt(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// Volume by muscle region over the last four weeks, for spotting a group you
/// have quietly stopped training.
struct RegionBalanceView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let totals = store.volumeByRegion()
        let ranked = totals.sorted { $0.value > $1.value }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Last four weeks")
                .font(.headline)

            if ranked.isEmpty {
                Text("Nothing logged yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(ranked, id: \.key) { entry in
                    BarMark(
                        x: .value("kg", entry.value),
                        y: .value("Muscle", entry.key.displayName)
                    )
                    .foregroundStyle(Color.orange.opacity(0.75))
                }
                .frame(height: CGFloat(ranked.count) * 22 + 20)

                let untrained = Set(MuscleRegion.allCases).subtracting(totals.keys)
                if !untrained.isEmpty {
                    Text("Untrained: " + untrained.map(\.displayName).sorted().joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
