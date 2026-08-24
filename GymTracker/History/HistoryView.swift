import SwiftUI
import GymKit

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    empty
                } else {
                    List(store.sessions.sorted { $0.startedAt > $1.startedAt }) { session in
                        row(for: session)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
        }
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

    private func row(for session: WorkoutSession) -> some View {
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
