import Foundation

/// A single highlightable region on the body map.
///
/// The raw values match the `data-region` attributes in `design/bodymap.html`,
/// which is what generates the artwork. Keep the two in step: if a region is
/// added here it needs a matching shape in the SVG, and vice versa.
public enum MuscleRegion: String, CaseIterable, Codable, Sendable {
    case chest
    case frontDelt
    case sideDelt
    case rearDelt
    case traps
    case lats
    case lowerBack
    case biceps
    case triceps
    case forearm
    case abs
    case obliques
    case quads
    case hamstrings
    case glutes
    case calves
    case adductors

    /// Which view the region is drawn on. Used to decide whether the Watch,
    /// which shows one view at a time, should open on the front or the back.
    public enum View: Sendable { case front, back, both }

    public var view: View {
        switch self {
        case .chest, .frontDelt, .abs, .obliques, .quads, .adductors, .biceps:
            return .front
        case .traps, .lats, .lowerBack, .rearDelt, .glutes, .hamstrings, .triceps:
            return .back
        case .sideDelt, .forearm, .calves:
            return .both
        }
    }

    /// Human-readable name for chips and labels.
    public var displayName: String {
        switch self {
        case .chest:      return "Chest"
        case .frontDelt:  return "Front delts"
        case .sideDelt:   return "Side delts"
        case .rearDelt:   return "Rear delts"
        case .traps:      return "Traps"
        case .lats:       return "Lats"
        case .lowerBack:  return "Lower back"
        case .biceps:     return "Biceps"
        case .triceps:    return "Triceps"
        case .forearm:    return "Forearms"
        case .abs:        return "Abs"
        case .obliques:   return "Obliques"
        case .quads:      return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes:     return "Glutes"
        case .calves:     return "Calves"
        case .adductors:  return "Adductors"
        }
    }
}

/// The coarse grouping a workout day is planned around.
///
/// Distinct from `MuscleRegion`, which is the fine-grained unit the body-map
/// artwork highlights. A group is what the user picks ("chest day"); regions
/// are what actually lights up.
public enum MuscleGroup: String, CaseIterable, Codable, Sendable {
    case chest
    case back
    case shoulders
    case arms
    case core
    case legs
    case glutes

    public var displayName: String {
        switch self {
        case .chest:     return "Chest"
        case .back:      return "Back"
        case .shoulders: return "Shoulders"
        case .arms:      return "Arms"
        case .core:      return "Core"
        case .legs:      return "Legs"
        case .glutes:    return "Glutes"
        }
    }

    /// Regions typically trained by this group, used when a day has no
    /// exercises yet and the map still needs something to show.
    public var regions: Set<MuscleRegion> {
        switch self {
        case .chest:     return [.chest, .frontDelt, .triceps]
        case .back:      return [.lats, .traps, .lowerBack, .biceps]
        case .shoulders: return [.frontDelt, .sideDelt, .rearDelt, .traps]
        case .arms:      return [.biceps, .triceps, .forearm]
        case .core:      return [.abs, .obliques]
        case .legs:      return [.quads, .hamstrings, .glutes, .calves, .adductors]
        case .glutes:    return [.glutes, .hamstrings]
        }
    }
}

/// A pre-rendered body-map image. Each case corresponds to one PNG in
/// `design/assets/bodymap/`, listed in that folder's `MANIFEST.json`.
public enum BodyMapKey: String, CaseIterable, Codable, Sendable {
    case rest
    case push
    case pull
    case legs
    case chest
    case back
    case shoulders
    case arms
    case core
    case fullBody

    /// Asset name to load. Matches the exported filename minus the extension.
    public var assetName: String {
        self == .fullBody ? "full-body" : rawValue
    }

    /// The regions this image highlights. Mirrors the `presets` map in
    /// `design/bodymap.html` - the two must agree or the artwork will not match
    /// the labels the app draws next to it.
    public var regions: Set<MuscleRegion> {
        switch self {
        case .rest:      return []
        case .push:      return [.chest, .frontDelt, .triceps]
        case .pull:      return [.lats, .traps, .rearDelt, .biceps, .forearm]
        case .legs:      return [.quads, .hamstrings, .glutes, .calves, .adductors]
        case .chest:     return [.chest, .frontDelt]
        case .back:      return [.lats, .traps, .lowerBack]
        case .shoulders: return [.frontDelt, .sideDelt, .rearDelt, .traps]
        case .arms:      return [.biceps, .triceps, .forearm]
        case .core:      return [.abs, .obliques]
        case .fullBody:  return Set(MuscleRegion.allCases)
        }
    }

    /// Best-fitting image for an arbitrary set of regions.
    ///
    /// Because the artwork is pre-rendered per day type, an exact match is not
    /// always available. Scoring is overlap over union rather than raw overlap:
    /// `fullBody` contains every region, so it wins any pure overlap count and
    /// a push day would light up the whole body. Dividing by the union
    /// penalises an image for highlighting muscles the session does not train.
    public static func bestMatch(for regions: Set<MuscleRegion>) -> BodyMapKey {
        guard !regions.isEmpty else { return .rest }
        return allCases
            .filter { $0 != .rest }
            .max { a, b in score(a, regions) < score(b, regions) } ?? .fullBody
    }

    private static func score(_ key: BodyMapKey, _ regions: Set<MuscleRegion>) -> Double {
        let union = key.regions.union(regions).count
        guard union > 0 else { return 0 }
        return Double(key.regions.intersection(regions).count) / Double(union)
    }
}
