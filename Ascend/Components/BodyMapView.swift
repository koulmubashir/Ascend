import SwiftUI
import AscendKit

/// Shows the pre-rendered body map for a set of muscle regions.
///
/// The artwork is one flat image per workout day type, exported from
/// `design/bodymap.html`. `BodyMapKey.bestMatch` picks the closest one for an
/// arbitrary region set. If the asset is missing the view falls back to `rest`,
/// then to a neutral placeholder, so the app runs before the art is final.
struct BodyMapView: View {
    let regions: Set<MuscleRegion>

    init(regions: Set<MuscleRegion>) {
        self.regions = regions
    }

    init(key: BodyMapKey) {
        self.regions = key.regions
    }

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
        .accessibilityLabel(accessibilityText)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.1))
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "figure.stand")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Body map artwork not added yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(1.15, contentMode: .fit)
    }

    private var accessibilityText: String {
        regions.isEmpty
            ? "Body map, nothing highlighted"
            : "Body map highlighting " + regions.map(\.displayName).sorted().joined(separator: ", ")
    }
}

/// Pills naming the muscle groups a day trains.
struct RegionChips: View {
    let regions: Set<MuscleRegion>

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(regions.map(\.displayName).sorted(), id: \.self) { name in
                Text(name)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.orange)
            }
        }
    }
}

/// Minimal wrapping stack. `Layout` needs iOS 16, which is the app's floor.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
