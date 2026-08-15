import AuroraCore
import AuroraModel
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Compact Stage Object palette for Edit Stage (C4B / C4.1) — Silhouette Kit + shapes.
///
/// C4.1: fills parent rail width (no fixed 220 pt). Category navigation is a
/// horizontally scrollable chip strip so all six sections remain reachable at narrow widths.
public struct StageObjectPaletteView: View {
    public var onPlaceStock: (StageStockAsset) -> Void
    public var onPlaceShape: (StageScenicKind) -> Void
    public var onImportImage: () -> Void

    @State private var category: PaletteSection = .performers
    @ObservedObject private var catalog = StageStockCatalog.shared

    public enum PaletteSection: String, CaseIterable, Identifiable {
        case performers = "Performers"
        case audience = "Audience"
        case equipment = "Equipment"
        case truss = "Truss"
        case special = "Special"
        case shapes = "Shapes"
        public var id: String { rawValue }

        /// Short label for compact chips.
        var chipLabel: String {
            switch self {
            case .performers: return "Performers"
            case .audience: return "Audience"
            case .equipment: return "Equipment"
            case .truss: return "Truss"
            case .special: return "Special"
            case .shapes: return "Shapes"
            }
        }

        var stockCategory: StageStockCategory? {
            switch self {
            case .performers: return .performers
            case .audience: return .audience
            case .equipment: return .equipment
            case .truss: return .truss
            case .special: return .special
            case .shapes: return nil
            }
        }
    }

    public init(
        onPlaceStock: @escaping (StageStockAsset) -> Void,
        onPlaceShape: @escaping (StageScenicKind) -> Void = { _ in },
        onImportImage: @escaping () -> Void = {}
    ) {
        self.onPlaceStock = onPlaceStock
        self.onPlaceShape = onPlaceShape
        self.onImportImage = onImportImage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("STAGE OBJECTS")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            categoryStrip
                .padding(.bottom, 6)

            ScrollView {
                if category == .shapes {
                    shapesGrid
                } else {
                    stockGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                onImportImage()
            } label: {
                Label("Import Image…", systemImage: "photo.badge.plus")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AuroraColor.surfacePanel)
    }

    /// Horizontally scrollable category chips — never clips off-screen categories.
    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(PaletteSection.allCases) { section in
                    Button {
                        category = section
                    } label: {
                        Text(section.chipLabel)
                            .font(.system(size: 10, weight: category == section ? .semibold : .regular))
                            .foregroundStyle(category == section ? Color.white : AuroraColor.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(category == section ? AuroraColor.accent : AuroraColor.surfaceRaised)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(section.rawValue)
                    .accessibilityLabel(section.rawValue)
                    .accessibilityAddTraits(category == section ? .isSelected : [])
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var stockGrid: some View {
        let assets = category.stockCategory.map { catalog.assets(in: $0) } ?? []
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 6)], spacing: 8) {
            ForEach(assets) { asset in
                Button {
                    onPlaceStock(asset)
                } label: {
                    StageStockThumbnail(asset: asset)
                }
                .buttonStyle(.plain)
                .help("Add \(asset.displayName) to Stage")
                .accessibilityLabel("Add \(asset.displayName) to Stage")
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shapesGrid: some View {
        let shapes: [(StageScenicKind, String, String)] = [
            (.rectangle, "Rectangle", "rectangle"),
            (.roundedRectangle, "Rounded Rect", "rectangle.roundedtop"),
            (.ellipse, "Ellipse", "oval"),
            (.triangle, "Triangle", "triangle"),
            (.line, "Line", "line.diagonal"),
            (.stageArea, "Stage Area", "rectangle.dashed"),
            (.label, "Text", "textformat"),
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 6)], spacing: 8) {
            ForEach(shapes, id: \.0) { kind, title, symbol in
                Button {
                    onPlaceShape(kind)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: symbol)
                            .font(.system(size: 20))
                            .frame(width: 40, height: 40)
                            .foregroundStyle(AuroraColor.textSecondary)
                        Text(title)
                            .font(.system(size: 9))
                            .foregroundStyle(AuroraColor.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 72)
                    }
                    .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(title) to Stage")
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
