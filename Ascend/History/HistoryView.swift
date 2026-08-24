import SwiftUI
import AscendKit

/// Everything you have done, wherever it was recorded.
///
/// Workouts logged in other apps appear alongside our own once Health is on,
/// visibly attributed rather than silently mixed in - so the list is complete
/// without pretending this app did the work.
struct HistoryView: View {
    @EnvironmentObject private var store: AppStore

    private var entries: [HealthSync.HistoryEntry] { store.combinedHistory }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    empty
                } else {
                    List(entries) { entry in
                        row(for: entry)
                    }
                    .listStyle(.plain)
                    .refreshable { await store.importFromHealth() }
                }
            }
            .navigationTitle("History")
        }
        .task { await store.importFromHealth() }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("No workouts yet")
                .font(.title3.weight(.semibold))
            Text("Finished sessions show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(for entry: HealthSync.HistoryEntry) -> some View {
        if let session = session(for: entry) {
            ownRow(for: session)
        } else {
            importedRow(for: entry)
        }
    }

    private func session(for entry: HealthSync.HistoryEntry) -> WorkoutSession? {
        guard let id = entry.sessionID else { return nil }
        return store.sessions.first { $0.id == id }
    }

    private func ownRow(for session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(session.startedAt.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.body.weight(.medium))
                Spacer()
                Image(systemName: session.isComplete ? "checkmark.circle.fill" : "circle.badge.exclamationmark")
                    .foregroundStyle(session.isComplete ? .green : .orange)
            }
            Text(detail(for: session))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let notes = session.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 3)
    }

    /// Dimmed and attributed, so it never reads as one of your logged sessions.
    private func importedRow(for entry: HealthSync.HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(entry.date.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "heart.text.square")
                    .foregroundStyle(.secondary)
            }
            Text(entry.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let source = entry.detail {
                Text("From \(appName(from: source))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }

    /// A bundle identifier is what dedup needs, but not what anyone wants to
    /// read - show the last component, which is close enough to the app name.
    private func appName(from bundleIdentifier: String) -> String {
        bundleIdentifier.split(separator: ".").last.map(String.init) ?? bundleIdentifier
    }

    private func detail(for session: WorkoutSession) -> String {
        let sets = session.setLogs.count
        let minutes = Int(session.totalActiveSeconds) / 60
        let volume = session.setLogs.reduce(0.0) { $0 + ($1.weightKg ?? 0) * Double($1.reps) }
        var parts = ["\(sets) set\(sets == 1 ? "" : "s")", "\(minutes) min"]
        if volume > 0 {
            parts.append("\(volume.formatted(.number.precision(.fractionLength(0)))) kg total")
        }
        return parts.joined(separator: " · ")
    }
}
