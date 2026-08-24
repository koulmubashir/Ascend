import Foundation

/// The seeded exercise catalogue.
///
/// Held as a value type so tests can build small fixtures instead of the full
/// default list.
public struct ExerciseLibrary: Codable, Sendable {
    public private(set) var all: [Exercise]
    private var byID: [UUID: Exercise]

    public init(all: [Exercise]) {
        self.all = all
        self.byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }

    public func exercise(id: UUID) -> Exercise? { byID[id] }

    public func exercises(for group: MuscleGroup) -> [Exercise] {
        all.filter { $0.group == group }
    }

    /// Swap candidates for an exercise: anything sharing a muscle region,
    /// excluding the exercise itself.
    public func alternates(for exercise: Exercise) -> [Exercise] {
        let explicit = exercise.alternateIDs.compactMap { byID[$0] }
        if !explicit.isEmpty { return explicit }

        return all.filter { candidate in
            candidate.id != exercise.id
                && !candidate.regions.isDisjoint(with: exercise.regions)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(all: try container.decode([Exercise].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(all)
    }
}

public extension ExerciseLibrary {

    /// Starter catalogue. Deliberately small and equipment-light - this is seed
    /// content, expected to be edited rather than treated as authoritative.
    static let starter: ExerciseLibrary = {
        func ex(_ name: String,
                _ group: MuscleGroup,
                _ regions: Set<MuscleRegion>,
                sets: Int = 3,
                reps: Int = 10,
                rest: Int = 90) -> Exercise {
            Exercise(name: name, group: group, regions: regions,
                     defaultSets: sets, defaultReps: reps, defaultRestSeconds: rest)
        }

        return ExerciseLibrary(all: [
            ex("Bench press", .chest, [.chest, .frontDelt, .triceps]),
            ex("Incline dumbbell press", .chest, [.chest, .frontDelt]),
            ex("Push-up", .chest, [.chest, .frontDelt, .triceps], reps: 15, rest: 60),
            ex("Cable fly", .chest, [.chest], reps: 12, rest: 60),

            ex("Pull-up", .back, [.lats, .biceps], reps: 8),
            ex("Barbell row", .back, [.lats, .traps, .biceps]),
            ex("Lat pulldown", .back, [.lats, .biceps], reps: 12),
            ex("Deadlift", .back, [.lowerBack, .lats, .hamstrings, .glutes], sets: 4, reps: 6, rest: 150),

            ex("Overhead press", .shoulders, [.frontDelt, .sideDelt, .triceps]),
            ex("Lateral raise", .shoulders, [.sideDelt], reps: 15, rest: 45),
            ex("Face pull", .shoulders, [.rearDelt, .traps], reps: 15, rest: 45),

            ex("Barbell curl", .arms, [.biceps], reps: 12, rest: 60),
            ex("Hammer curl", .arms, [.biceps, .forearm], reps: 12, rest: 60),
            ex("Triceps pushdown", .arms, [.triceps], reps: 12, rest: 60),
            ex("Overhead triceps extension", .arms, [.triceps], reps: 12, rest: 60),

            ex("Plank", .core, [.abs], sets: 3, reps: 1, rest: 45),
            ex("Hanging leg raise", .core, [.abs], reps: 12, rest: 60),
            ex("Russian twist", .core, [.obliques], reps: 20, rest: 45),

            ex("Back squat", .legs, [.quads, .glutes, .adductors], sets: 4, reps: 8, rest: 150),
            ex("Leg press", .legs, [.quads, .glutes], reps: 12, rest: 120),
            ex("Romanian deadlift", .legs, [.hamstrings, .glutes], reps: 10, rest: 120),
            ex("Calf raise", .legs, [.calves], reps: 15, rest: 45),

            ex("Hip thrust", .glutes, [.glutes, .hamstrings], reps: 12, rest: 90),
            ex("Bulgarian split squat", .glutes, [.glutes, .quads], reps: 10, rest: 90)
        ])
    }()
}
