import SwiftUI
import WidgetKit
import AscendKit

/// Next workout on the watch face.
///
/// Reads a small snapshot the Watch app writes to its own container. It
/// deliberately does not reach across to the phone: a complication has to
/// render whether or not the phone is anywhere nearby.
@main
struct AscendWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextWorkoutComplication()
    }
}

struct NextWorkoutComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextWorkoutWatch", provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next workout")
        .description("What you are training next.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct ComplicationEntry: TimelineEntry {
    var date: Date
    var snapshot: WatchFaceSnapshot?
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: Date(), snapshot: WatchFaceSnapshot.read() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let entry = ComplicationEntry(date: Date(), snapshot: WatchFaceSnapshot.read())
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date().addingTimeInterval(7200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    private var name: String { entry.snapshot?.workoutName ?? "No plan" }
    private var day: String { entry.snapshot?.dayLabel ?? "" }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(day) · \(name)")
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.caption)
                Text(name.prefix(4))
                    .font(.system(size: 11, weight: .semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(day.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                if let snapshot = entry.snapshot {
                    Text("\(snapshot.exerciseCount) exercises")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
