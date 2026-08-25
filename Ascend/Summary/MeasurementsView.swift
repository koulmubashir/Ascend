import SwiftUI
import Charts
import AscendKit

/// Body weight and tape measurements, with a chart per tracked kind.
struct MeasurementsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var logging: MeasurementKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                quickAdd

                let tracked = store.trackedMeasurements
                if tracked.isEmpty {
                    empty
                } else {
                    ForEach(tracked, id: \.self) { kind in
                        card(for: kind)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Measurements")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $logging) { kind in
            LogMeasurementSheet(kind: kind)
        }
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Record")
                .font(.headline)
            FlowLayout(spacing: 8) {
                ForEach(MeasurementKind.allCases, id: \.self) { kind in
                    Button {
                        logging = kind
                    } label: {
                        Text(kind.displayName)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                            .foregroundStyle(Color.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Nothing recorded yet")
                .font(.title3.weight(.semibold))
            Text("Pick something above to record your first measurement.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func card(for kind: MeasurementKind) -> some View {
        let series = store.measurementSeries(kind)
        let latest = series.last

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind.displayName)
                    .font(.headline)
                Spacer()
                if let latest {
                    Text("\(fmt(latest.value)) \(kind.unit)")
                        .font(.headline)
                        .monospacedDigit()
                }
            }

            if let change = store.measurementChange(kind) {
                Text(changeText(change, kind: kind))
                    .font(.caption)
                    .foregroundStyle(tint(for: change, kind: kind))
            }

            if series.count >= 2 {
                Chart(series) { point in
                    LineMark(
                        x: .value("Date", point.recordedAt),
                        y: .value(kind.unit, point.value)
                    )
                    .foregroundStyle(Color.orange)
                    .interpolationMethod(.monotone)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 130)
            }

            if let latest {
                HStack {
                    Text(latest.recordedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Undo") { store.removeMeasurement(latest) }
                        .font(.caption)
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private func changeText(_ change: Double, kind: MeasurementKind) -> String {
        let sign = change > 0 ? "+" : ""
        return "\(sign)\(fmt(change)) \(kind.unit) over the last 90 days"
    }

    /// Body weight gets no colour - people are cutting or bulking and the app
    /// has no business deciding which direction is good.
    private func tint(for change: Double, kind: MeasurementKind) -> Color {
        guard kind.lowerIsTypicallyBetter, change != 0 else { return .secondary }
        return change < 0 ? .green : .orange
    }

    private func fmt(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

struct LogMeasurementSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let kind: MeasurementKind

    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Value in \(kind.unit)", text: $text)
                        .keyboardType(.decimalPad)
                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Between \(Int(kind.plausibleRange.lowerBound)) and \(Int(kind.plausibleRange.upperBound)) \(kind.unit).")
                }
            }
            .navigationTitle(kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { submit() }
                }
            }
        }
    }

    private func submit() {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")) else {
            error = "Enter a number."
            return
        }
        guard store.logMeasurement(kind: kind, value: value) else {
            error = "That looks off — check the decimal point."
            return
        }
        dismiss()
    }
}

