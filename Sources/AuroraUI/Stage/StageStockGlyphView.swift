import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Renders a stock silhouette (or missing-asset placeholder) for Stage canvas / palette.
public struct StageStockGlyphView: View {
    public var assetKey: String
    public var opacity: Double
    public var selected: Bool
    public var locked: Bool
    public var size: CGSize

    public init(
        assetKey: String,
        opacity: Double = 0.9,
        selected: Bool = false,
        locked: Bool = false,
        size: CGSize = CGSize(width: 80, height: 120)
    ) {
        self.assetKey = assetKey
        self.opacity = opacity
        self.selected = selected
        self.locked = locked
        self.size = size
    }

    public var body: some View {
        let catalog = StageStockCatalog.shared
        let asset = catalog.asset(key: assetKey)
        // Exact size frame so Stage canvas rotation/position pivot is the object center.
        ZStack {
            if let asset, let nsImage = catalog.image(for: asset) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .opacity(opacity)
                    .colorMultiply(Color.white)
            } else {
                missingPlaceholder
            }
            if selected {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(AuroraColor.accentBright, lineWidth: 1.5)
                    .frame(width: size.width, height: size.height)
            }
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AuroraColor.warning)
                    .offset(x: size.width * 0.35, y: -size.height * 0.4)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var missingPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: size.width, height: size.height)
            VStack(spacing: 2) {
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: min(size.width, size.height) * 0.25))
                Text("Missing")
                    .font(.system(size: 9))
            }
            .foregroundStyle(Color.white.opacity(0.5))
        }
        .opacity(opacity)
    }
}

/// Compact palette thumbnail.
public struct StageStockThumbnail: View {
    public var asset: StageStockAsset
    public var selected: Bool

    public init(asset: StageStockAsset, selected: Bool = false) {
        self.asset = asset
        self.selected = selected
    }

    public var body: some View {
        VStack(spacing: 4) {
            StageStockGlyphView(
                assetKey: asset.key,
                opacity: asset.defaultOpacity,
                selected: selected,
                size: CGSize(width: 44, height: 52)
            )
            Text(asset.displayName)
                .font(.system(size: 9))
                .foregroundStyle(AuroraColor.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 64)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? AuroraColor.surfaceSelected : Color.clear)
        )
    }
}
