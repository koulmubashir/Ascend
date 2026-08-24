import SwiftUI
import WidgetKit
import AscendKit

/// Home screen widget: what is next, and how the week is going.
///
/// Reads a small snapshot the app writes into the shared App Group container
/// rather than the whole store - the widget only needs a handful of fields, and
/// decoding the full history on every timeline refresh would be wasteful.
struct NextWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextWorkout", provider: NextWorkoutProvider()) { entry in
            // containerBackground is iOS 17+. On 16.x the widget still renders,
            // it just uses the system default background.
            if #available(iOS 17.0, *) {
                NextWorkoutView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                NextWorkoutView(entry: entry)
                    .padding()
            }
        }
        .configurationDisplayName("Next workout")
        .description("Your next session and this week's progress.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NextWorkoutEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?
}

struct NextWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextWorkoutEntry {
        NextWorkoutEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextWorkoutEntry) -> Void) {
        completion(NextWorkoutEntry(date: Date(), snapshot: WidgetSnapshot.read() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextWorkoutEntry>) -> Void) {
        let entry = NextWorkoutEntry(date: Date(), snapshot: WidgetSnapshot.read())
        // Refresh on the hour. The app also reloads timelines whenever the plan
        // changes, so this is only a backstop for a day rolling over.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct NextWorkoutView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextWorkoutEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(.orange)
                Text("Open Ascend to set up a plan")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func content(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.dayLabel.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if snapshot.streak > 0 {
                    Label("\(snapshot.streak)", systemImage: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Text(snapshot.workoutName)
                .font(family == .systemSmall ? .headline : .title3.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if family == .systemMedium, !snapshot.groups.isEmpty {
                Text(snapshot.groups.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            HStack(spacing: 4) {
                ForEach(0..<snapshot.totalThisWeek, id: \.self) { index in
                    Circle()
                        .fill(index < snapshot.doneThisWeek ? Color.orange : Color.secondary.opacity(0.28))
                        .frame(width: 7, height: 7)
                }
                Spacer()
                Text("\(snapshot.doneThisWeek)/\(snapshot.totalThisWeek)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
