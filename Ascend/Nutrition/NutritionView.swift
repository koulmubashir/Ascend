import SwiftUI
import AscendKit

/// Protein and water logging. Only reachable when at least one of the two is
/// switched on in Settings, so people who do not want it never see it.
struct NutritionView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingManualEntry: IntakeKind?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if store.settings.proteinTrackingEnabled {
                        card(for: .protein)
                    }
                    if store.settings.waterTrackingEnabled {
                        card(for: .water)
                    }
                    if !store.settings.proteinTrackingEnabled && !store.settings.waterTrackingEnabled {
                        empty
                    }
                }
                .padding(20)
            }
            .navigationTitle("Intake")
            .sheet(item: $showingManualEntry) { kind in
                ManualIntakeSheet(kind: kind)
            }
        }
    }

    private func card(for kind: IntakeKind) -> some View {
        let total = store.displayTotal(for: kind)
        let goal = store.goal(for: kind)
        let progress = IntakeTracker.progress(total: total, goal: goal)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(kind.displayName)
                    .font(.headline)
                Spacer()
                Text("\(format(total)) / \(format(goal)) \(kind.unit)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(value: progress)
                .tint(.orange)

            HStack(spacing: 8) {
                ForEach(kind.presets, id: \.self) { amount in
                    Button {
                        store.logIntake(kind: kind, amount: amount)
                    } label: {
                        Text("+\(format(amount))")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(Color.orange)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showingManualEntry = kind
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.medium))
                        .frame(width: 44)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Enter \(kind.displayName.lowercased()) amount")
            }

            weekStrip(for: kind)

            if let last = store.lastEntry(for: kind) {
                HStack {
                    Text("Last: \(format(last.amount)) \(kind.unit) at \(last.loggedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Undo") { store.removeIntake(last) }
                        .font(.caption)
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    /// Seven bars, today last. Enough to see a pattern without a chart library.
    private func weekStrip(for kind: IntakeKind) -> some View {
        let totals = store.weeklyTotals(for: kind)
        let goal = store.goal(for: kind)

        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(totals.enumerated()), id: \.offset) { _, day in
                let fraction = IntakeTracker.progress(total: day.total, goal: goal)
                RoundedRectangle(cornerRadius: 3)
                    .fill(fraction >= 1 ? Color.orange : Color.orange.opacity(0.35))
                    .frame(height: max(3, 34 * fraction))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 34)
        .accessibilityLabel("Last seven days of \(kind.displayName.lowercased())")
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "drop")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Tracking is off")
                .font(.title3.weight(.semibold))
            Text("Turn on protein or water in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 60)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

/// Manual amount entry for anything the preset buttons do not cover.
struct ManualIntakeSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let kind: IntakeKind

    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Amount in \(kind.unit)", text: $text)
                        .keyboardType(.numberPad)
                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add \(kind.displayName.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { submit() }
                }
            }
        }
    }

    private func submit() {
        guard let amount = Double(text.trimmingCharacters(in: .whitespaces)), amount > 0 else {
            error = "Enter a number greater than zero."
            return
        }
        store.logIntake(kind: kind, amount: amount)
        dismiss()
    }
}

extension IntakeKind: Identifiable {
    public var id: String { rawValue }
}
