import SwiftUI
import AscendKit

/// Renders the body-map artwork for a workout day.
///
/// Artwork is one flat image per day type, named in
/// design/assets/bodymap/MANIFEST.json. When an image is missing the view falls
/// back to `rest`, then to a neutral placeholder - so the app builds and runs
/// before the artwork lands.
struct MuscleBodyMapView: View {
    let key: BodyMapKey
    var groups: [MuscleGroup] = []

    var body: some View {
        Group {
            if let image = resolvedImage {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var resolvedImage: Image? {
        if let ui = UIImage(named: key.assetName) { return Image(uiImage: ui) }
        if let ui = UIImage(named: BodyMapKey.rest.assetName) { return Image(uiImage: ui) }
        return nil
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(.secondarySystemBackground))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "figure.arms.open")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(groups.isEmpty ? "Rest day" : groups.map(\.displayName).joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            )
            .aspectRatio(1440.0 / 870.0, contentMode: .fit)
    }

    private var accessibilityText: String {
        groups.isEmpty
            ? "Rest day, no muscles targeted"
            : "Targeting " + groups.map(\.displayName).joined(separator: ", ")
    }
}

extension MuscleGroup {
    var displayName: String {
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
}
