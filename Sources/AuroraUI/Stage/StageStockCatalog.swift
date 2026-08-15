import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Categories in the Aurora Silhouette Kit / Stage Object palette.
public enum StageStockCategory: String, CaseIterable, Identifiable, Sendable, Hashable {
    case performers
    case audience
    case equipment
    case truss
    case special
    case shapes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .performers: return "Performers"
        case .audience: return "Audience"
        case .equipment: return "Equipment"
        case .truss: return "Truss"
        case .special: return "Special"
        case .shapes: return "Shapes"
        }
    }
}

/// Normalized content bounds within the source asset (0…1).
public struct StageAssetVisualBounds: Equatable, Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public static let full = StageAssetVisualBounds(x: 0, y: 0, width: 1, height: 1)

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = min(1, max(0, x))
        self.y = min(1, max(0, y))
        self.width = min(1, max(0.01, width))
        self.height = min(1, max(0.01, height))
    }

    public var isFull: Bool {
        x <= 0.001 && y <= 0.001 && width >= 0.999 && height >= 0.999
    }
}

/// One stock asset from Catalog.json (stable key is document identity).
public struct StageStockAsset: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let displayName: String
    public let category: StageStockCategory
    public let defaultOpacity: Double
    public let defaultTint: String
    public let png1xRelative: String
    public let png2xRelative: String
    public let svgRelative: String
    /// Preferred Stage world size at placement (after catalog → world conversion).
    public let defaultStageWidth: Double
    public let defaultStageHeight: Double
    /// width / height of preferred Stage footprint (from placement size, not source square).
    public let intrinsicAspectRatio: Double
    /// Useful non-transparent content within the source bitmap (normalized).
    /// Corrected kit uses full `(0,0,1,1)` — assets are pre-isolated.
    public let visualBounds: StageAssetVisualBounds
    /// Kit quality flag from corrected catalog (optional).
    public let sourceStatus: String?

    /// Suggested placement size (width × height) in Stage world units.
    public var defaultSize: CGSize {
        CGSize(width: defaultStageWidth, height: defaultStageHeight)
    }
}

/// Loads bundled Silhouette Kit metadata and resolves image resources.
///
/// **Corrected kit (C4.2+):** `Resources/StageAssets` ships
/// `Aurora Stage Silhouette Kit — Corrected` with isolated SVG/PNG masters.
/// Catalog `defaultStageSize` is in abstract meters; converted to Stage world via
/// `catalogMetersToStageWorld`.
@MainActor
public final class StageStockCatalog: ObservableObject {
    public static let shared = StageStockCatalog()

    /// Multiplier from catalog `defaultStageSize` (meters-like) → Stage world units.
    /// ~80 maps a 15 m stage width to the default 1200-unit canvas.
    public static let catalogMetersToStageWorld: Double = 80

    public private(set) var assets: [StageStockAsset] = []
    public private(set) var didLoad = false
    public private(set) var loadError: String?
    public private(set) var kitName: String?

    private init() {
        reload()
    }

    public func reload() {
        loadError = nil
        kitName = nil
        guard let url = Self.catalogURL() else {
            loadError = "Catalog.json not found in StageAssets bundle"
            assets = []
            didLoad = true
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let dto = try JSONDecoder().decode(CatalogDTO.self, from: data)
            kitName = dto.kit
            assets = dto.assets.compactMap { row in
                Self.makeAsset(from: row)
            }
            didLoad = true
        } catch {
            loadError = error.localizedDescription
            assets = []
            didLoad = true
        }
    }

    public func asset(key: String) -> StageStockAsset? {
        assets.first { $0.key == key }
    }

    public func assets(in category: StageStockCategory) -> [StageStockAsset] {
        assets.filter { $0.category == category }
    }

    /// Palette sections excluding pure shapes (shapes are synthetic).
    public var paletteCategories: [StageStockCategory] {
        [.performers, .audience, .equipment, .truss, .special]
    }

    // MARK: - Mapping

    private static func makeAsset(from row: AssetDTO) -> StageStockAsset? {
        guard let cat = StageStockCategory(rawValue: row.category) else { return nil }
        let heuristic = heuristicDefaultSize(key: row.key, category: cat)

        // Prefer corrected kit `defaultStageSize` (meters), then legacy flat fields, then heuristic.
        let w: Double
        let h: Double
        if let size = row.defaultStageSize {
            w = size.width * catalogMetersToStageWorld
            h = size.height * catalogMetersToStageWorld
        } else if let dw = row.defaultStageWidth, let dh = row.defaultStageHeight {
            // Legacy catalogs already stored Stage-world units.
            w = dw
            h = dh
        } else {
            w = heuristic.width
            h = heuristic.height
        }

        // Placement footprint aspect (not source bitmap square).
        let placementAR = w / max(h, 0.001)
        let ar = row.intrinsicAspectRatio.flatMap { catalogAR -> Double? in
            // Corrected kit often stores 1.0 for square masters while defaultStageSize is elongated —
            // prefer placement aspect when catalog AR is ~1 but size is not.
            if abs(catalogAR - 1.0) < 0.05, abs(placementAR - 1.0) > 0.15 {
                return placementAR
            }
            return catalogAR
        } ?? placementAR

        let vb: StageAssetVisualBounds
        if let b = row.visualBounds {
            vb = StageAssetVisualBounds(x: b.x, y: b.y, width: b.width, height: b.height)
        } else {
            vb = .full
        }

        return StageStockAsset(
            key: row.key,
            displayName: row.displayName,
            category: cat,
            defaultOpacity: row.defaultOpacity ?? 0.9,
            defaultTint: row.defaultTint ?? "#FFFFFF",
            png1xRelative: row.png1x,
            png2xRelative: row.png2x,
            svgRelative: row.svg,
            defaultStageWidth: w,
            defaultStageHeight: h,
            intrinsicAspectRatio: ar,
            visualBounds: vb,
            sourceStatus: row.sourceStatus
        )
    }

    // MARK: - Resource resolution

    public func image(for key: String) -> NSImage? {
        guard let asset = asset(key: key) else { return nil }
        return image(for: asset)
    }

    public func image(for asset: StageStockAsset) -> NSImage? {
        if let img = bundleImage(relativePath: asset.png2xRelative)
            ?? bundleImage(relativePath: asset.png1xRelative)
        {
            // Corrected kit is pre-isolated (visualBounds full) — crop is a no-op.
            return crop(img, to: asset.visualBounds)
        }
        return nil
    }

    /// Crop source image to normalized visualBounds (identity if full).
    /// `visualBounds` uses top-left origin (same as PNG/CGImage).
    public func crop(_ image: NSImage, to bounds: StageAssetVisualBounds) -> NSImage {
        if bounds.isFull {
            return image
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else {
            return image
        }
        let pw = CGFloat(cg.width)
        let ph = CGFloat(cg.height)
        guard pw > 1, ph > 1 else { return image }
        let cropRect = CGRect(
            x: bounds.x * Double(pw),
            y: bounds.y * Double(ph),
            width: bounds.width * Double(pw),
            height: bounds.height * Double(ph)
        ).integral
        guard let cropped = cg.cropping(to: cropRect) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: cropRect.width, height: cropRect.height))
    }

    private func bundleImage(relativePath: String) -> NSImage? {
        let parts = relativePath.split(separator: "/").map(String.init)
        guard let file = parts.last else { return nil }
        let name = (file as NSString).deletingPathExtension
        let subdir = parts.dropLast().joined(separator: "/")

        if let root = Bundle.module.resourceURL?.appendingPathComponent("StageAssets") {
            let url = root.appendingPathComponent(relativePath)
            if let img = NSImage(contentsOf: url) { return img }
            if let alt = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "StageAssets/\(subdir)") {
                return NSImage(contentsOf: alt)
            }
        }
        if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: subdir) {
            return NSImage(contentsOf: url)
        }
        return nil
    }

    private static func catalogURL() -> URL? {
        if let root = Bundle.module.resourceURL?.appendingPathComponent("StageAssets/Catalog.json"),
           FileManager.default.fileExists(atPath: root.path) {
            return root
        }
        return Bundle.module.url(forResource: "Catalog", withExtension: "json", subdirectory: "StageAssets")
            ?? Bundle.module.url(forResource: "Catalog", withExtension: "json")
    }

    /// Fallback sizes when catalog omits defaults (legacy catalog entries).
    /// Values are already in Stage world units (not meters).
    public static func heuristicDefaultSize(key: String, category: StageStockCategory) -> CGSize {
        let m = catalogMetersToStageWorld
        switch category {
        case .performers:
            // ~0.85 × 1.8 m
            return CGSize(width: 0.85 * m, height: 1.8 * m)
        case .audience:
            return CGSize(width: 4.0 * m, height: 1.5 * m)
        case .equipment:
            return CGSize(width: 0.9 * m, height: 1.8 * m)
        case .truss:
            if key.contains("circle") || key.contains("curved") {
                return CGSize(width: 1.8 * m, height: 1.8 * m)
            }
            if key.contains("long") {
                return CGSize(width: 4.0 * m, height: 0.55 * m)
            }
            return CGSize(width: 2.4 * m, height: 0.55 * m)
        case .special:
            return CGSize(width: 1.2 * m, height: 1.2 * m)
        case .shapes:
            return CGSize(width: 120, height: 80)
        }
    }

    // MARK: - DTO

    private struct CatalogDTO: Decodable {
        var schemaVersion: Int?
        var kit: String?
        var assets: [AssetDTO]
    }

    private struct AssetDTO: Decodable {
        var key: String
        var displayName: String
        var category: String
        var defaultTint: String?
        var defaultOpacity: Double?
        var svg: String
        var png1x: String
        var png2x: String
        /// Legacy flat Stage-world defaults (pre-corrected kit).
        var defaultStageWidth: Double?
        var defaultStageHeight: Double?
        /// Corrected kit meters-like size.
        var defaultStageSize: SizeDTO?
        var intrinsicAspectRatio: Double?
        var visualBounds: BoundsDTO?
        var sourceStatus: String?
        var normalizedPaddingFraction: Double?
        var containsEmbeddedText: Bool?
    }

    private struct SizeDTO: Decodable {
        var width: Double
        var height: Double
    }

    private struct BoundsDTO: Decodable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }
}
