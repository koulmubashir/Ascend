import Foundation

/// Turns "I want to train N days a week" into a concrete weekly plan.
///
/// Deterministic templates - no randomness, no ML. Picking the same number of
/// days twice always gives the same split.
public enum PlanBuilder {

    public static func trainingDays(forDaysPerWeek days: Int, library: ExerciseLibrary) -> [TrainingDay] {
        let split = Split.forDaysPerWeek(days)
        return split.dayTemplates.enumerated().map { index, template in
            TrainingDay(
                name: template.name,
                orderInWeek: index,
                groups: template.groups,
                bodyMapKey: template.bodyMapKey,
                plannedExercises: plannedExercises(for: template.groups, library: library)
            )
        }
    }

    /// Dates the first week of a plan, starting from the next day.
    public static func schedule(
        days: [TrainingDay],
        startingAfter date: Date,
        calendar: Calendar = .current
    ) -> [ScheduledWorkout] {
        guard !days.isEmpty else { return [] }

        // Spread the sessions across the week rather than stacking them up front,
        // so rest days actually fall between training days.
        let stride = max(1, 7 / days.count)
        var result: [ScheduledWorkout] = []
        var cursor = calendar.startOfDay(for: date)

        for day in days {
            guard let next = calendar.date(byAdding: .day, value: stride, to: cursor) else { break }
            cursor = next
            result.append(ScheduledWorkout(trainingDay: day, scheduledDate: cursor))
        }
        return result
    }

    static func plannedExercises(for groups: [MuscleGroup], library: ExerciseLibrary) -> [PlannedExercise] {
        var planned: [PlannedExercise] = []
        var order = 0
        for group in groups {
            // Two movements per group keeps sessions to a sensible length.
            for exercise in library.exercises(for: group).prefix(2) {
                // The whole Exercise is embedded rather than referenced by id so
                // a planned day is self-contained - the Watch can run a session
                // from a synced payload without access to the library.
                planned.append(PlannedExercise(
                    exercise: exercise,
                    orderIndex: order,
                    targetSets: exercise.defaultSets,
                    targetReps: exercise.defaultReps,
                    restSeconds: exercise.defaultRestSeconds
                ))
                order += 1
            }
        }
        return planned
    }

    // MARK: - Splits

    struct DayTemplate {
        let name: String
        let groups: [MuscleGroup]
        let bodyMapKey: BodyMapKey
    }

    enum Split {
        case fullBody, upperLower, pushPullLegs, fourDay, fiveDay, sixDay

        static func forDaysPerWeek(_ days: Int) -> Split {
            switch max(1, min(days, 6)) {
            case 1, 2: return .fullBody
            case 3:    return .pushPullLegs
            case 4:    return .fourDay
            case 5:    return .fiveDay
            default:   return .sixDay
            }
        }

        var dayTemplates: [DayTemplate] {
            switch self {
            case .fullBody:
                return [
                    DayTemplate(name: "Full body", groups: [.chest, .back, .legs, .core], bodyMapKey: .fullBody),
                    DayTemplate(name: "Full body", groups: [.shoulders, .arms, .legs, .core], bodyMapKey: .fullBody)
                ]
            case .upperLower:
                return [
                    DayTemplate(name: "Upper", groups: [.chest, .back, .shoulders, .arms], bodyMapKey: .push),
                    DayTemplate(name: "Lower", groups: [.legs, .glutes, .core], bodyMapKey: .legs)
                ]
            case .pushPullLegs:
                return [
                    DayTemplate(name: "Push", groups: [.chest, .shoulders], bodyMapKey: .push),
                    DayTemplate(name: "Pull", groups: [.back, .arms], bodyMapKey: .pull),
                    DayTemplate(name: "Legs", groups: [.legs, .glutes], bodyMapKey: .legs)
                ]
            case .fourDay:
                return [
                    DayTemplate(name: "Push", groups: [.chest, .shoulders], bodyMapKey: .push),
                    DayTemplate(name: "Pull", groups: [.back, .arms], bodyMapKey: .pull),
                    DayTemplate(name: "Legs", groups: [.legs, .glutes], bodyMapKey: .legs),
                    DayTemplate(name: "Core", groups: [.core, .arms], bodyMapKey: .core)
                ]
            case .fiveDay:
                return [
                    DayTemplate(name: "Chest", groups: [.chest], bodyMapKey: .chest),
                    DayTemplate(name: "Back", groups: [.back], bodyMapKey: .back),
                    DayTemplate(name: "Legs", groups: [.legs, .glutes], bodyMapKey: .legs),
                    DayTemplate(name: "Shoulders", groups: [.shoulders], bodyMapKey: .shoulders),
                    DayTemplate(name: "Arms", groups: [.arms, .core], bodyMapKey: .arms)
                ]
            case .sixDay:
                return [
                    DayTemplate(name: "Push", groups: [.chest, .shoulders], bodyMapKey: .push),
                    DayTemplate(name: "Pull", groups: [.back], bodyMapKey: .pull),
                    DayTemplate(name: "Legs", groups: [.legs], bodyMapKey: .legs),
                    DayTemplate(name: "Shoulders", groups: [.shoulders], bodyMapKey: .shoulders),
                    DayTemplate(name: "Arms", groups: [.arms], bodyMapKey: .arms),
                    DayTemplate(name: "Core", groups: [.core, .glutes], bodyMapKey: .core)
                ]
            }
        }
    }
}
