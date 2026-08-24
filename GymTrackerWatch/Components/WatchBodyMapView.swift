import SwiftUI
import GymKit

/// Watch-sized body map.
///
/// Shares `BodyMapKey` with the phone, so both sides pick the same artwork for
/// the same regions. The Watch has its own asset catalog holding downscaled
/// copies - shipping the phone's 1840px images to the wrist would bloat the
/// bundle for no visible gain on a 40mm screen.
struct WatchBodyMapView: View {
    let regions: Set<MuscleRegion>

    private var key: BodyMapKey { BodyMapKey.bestMatch(for: regions) }

    var body: some View {
        Group {
            if let image = UIImage(named: key.assetName) ?? UIImage(named: BodyMapKey.rest.assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        }
        .accessibilityLabel(
            regions.isEmpty
                ? "Body map"
                : "Training " + regions.map(\.displayName).sorted().joined(separator: ", ")
        )
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .overlay {
                Image(systemName: "figure.stand")
                    .foregroundStyle(.secondary)
            }
    }
}
