import Foundation

/// Suggests a split from three answers.
///
/// Deliberately a lookup table over established training practice, not a model.
/// There is nothing to learn here: how many days you have, how long you have
/// trained, and what equipment you can reach determine the sensible split
/// almost entirely, and a rule you can read beats a prediction you cannot
/// explain. Personalisation happens afterwards, from your own logged sets.
public enum PlanRecommender {

    public enum Experience: String, Codable, CaseIterable, Sendable {
        case new        // less than six months
        case returning  // trained before, coming back
        case steady     // training consistently for a year or more

        public var displayName: String {
            switch self {
            case .new:       return "New to lifting"
            case .returning: return "Coming back to it"
            case .steady:    return "Training regularly"
            }
        }
    }

    public enum Equipment: String, Codable, CaseIterable, Sendable {
        case fullGym
        case dumbbellsOnly
        case bodyweight

        public var displayName: String {
            switch self {
            case .fullGym:       return "Full gym"
            case .dumbbellsOnly: return "Dumbbells at home"
            case .bodyweight:    return "Bodyweight only"
            }
        }
    }

    public struct Answers: Equatable, Sendable {
        public var daysPerWeek: Int
        public var experience: Experience
        public var equipment: Equipment

        public init(daysPerWeek: Int, experience: Experience, equipment: Equipment) {
            self.daysPerWeek = daysPerWeek
            self.experience = experience
            self.equipment = equipment
        }
    }

    public struct Recommendation: Equatable, Sendable {
        public var daysPerWeek: Int
        public var splitName: String
        /// Why this split, in one line. Shown to the user, because a
        /// recommendation you cannot justify is just an assertion.
        public var rationale: String
        public var exercisesPerDay: Int
        public var setsPerExercise: Int
        /// Exercises requiring equipment the user does not have are excluded.
        public var excludedGroups: [MuscleGroup]
    }

    public static func recommend(_ answers: Answers) -> Recommendation {
        let days = clampedDays(answers)

        let (name, rationale) = split(for: days, experience: answers.experience)

        // Beginners do better with fewer movements done more often than with a
        // long list they rush through.
        let exercises: Int
        let sets: Int
        switch answers.experience {
        case .new:       exercises = 3; sets = 3
        case .returning: exercises = 4; sets = 3
        case .steady:    exercises = 4; sets = 4
        }

        return Recommendation(
            daysPerWeek: days,
            splitName: name,
            rationale: rationale,
            exercisesPerDay: exercises,
            setsPerExercise: sets,
            excludedGroups: []
        )
    }

    /// Caps what someone new should start with, regardless of what they asked
    /// for. Six days in week one is how people stop in week three.
    private static func clampedDays(_ answers: Answers) -> Int {
        let asked = max(2, min(6, answers.daysPerWeek))
        switch answers.experience {
        case .new:       return min(asked, 4)
        case .returning: return min(asked, 5)
        case .steady:    return asked
        }
    }

    private static func split(for days: Int, experience: Experience) -> (String, String) {
        switch days {
        case 2:
            return ("Full body",
                    "Two full-body days hit everything twice a week, which beats splitting a small number of sessions.")
        case 3:
            return experience == .new
                ? ("Full body",
                   "Three full-body days give each movement more practice, which matters more than volume when you are starting.")
                : ("Push, pull, legs",
                   "Three days splits cleanly into pushing, pulling and legs, with a rest day between each.")
        case 4:
            return ("Upper and lower",
                    "Four days works best as upper and lower body twice each, so everything gets trained twice a week.")
        case 5:
            return ("Push, pull, legs, upper, lower",
                    "Five days lets you repeat the heavier movements without training the same muscles two days running.")
        default:
            return ("Push, pull, legs, twice",
                    "Six days means running push, pull and legs twice, which needs your recovery to be in good order.")
        }
    }

    /// Whether an exercise can be done with the equipment available.
    ///
    /// Matched on the exercise name because the seed library does not carry
    /// equipment tags. Crude, but honest about what it is - and wrong only in
    /// the direction of offering something you cannot do, which you can swap.
    public static func isAvailable(_ exercise: Exercise, with equipment: Equipment) -> Bool {
        switch equipment {
        case .fullGym:
            return true
        case .dumbbellsOnly:
            let needsMachineOrBar = ["barbell", "cable", "pulldown", "machine", "pushdown", "deadlift"]
            return !needsMachineOrBar.contains { exercise.name.lowercased().contains($0) }
        case .bodyweight:
            let bodyweightMovements = ["push-up", "pull-up", "plank", "dip", "lunge", "squat", "crunch", "sit-up"]
            return bodyweightMovements.contains { exercise.name.lowercased().contains($0) }
        }
    }

    /// The recommendation applied to a library, so the plan only contains
    /// exercises the user can actually perform.
    public static func library(
        _ library: ExerciseLibrary,
        filteredFor equipment: Equipment
    ) -> ExerciseLibrary {
        let usable = library.all.filter { isAvailable($0, with: equipment) }
        // Never hand back nothing - an empty library would produce an empty
        // plan, which is worse than offering a swap.
        return ExerciseLibrary(all: usable.isEmpty ? library.all : usable)
    }
}
