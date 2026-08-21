import Foundation

// MARK: - Fixture placement

public enum StageBeamRenderMode: String, Codable, CaseIterable, Sendable, Hashable {
    case directional
    case softGlow
}

/// Persisted 2D stage placement (P0-A). Does **not** affect DMX patch or fixture existence.
///
/// C4.1: physical Stage beam visualization is independent of DMX Pan/Tilt.
/// - `rotation` = fixture body/glyph orientation on the plot
/// - `aimDirection` = direction light travels on the 2D plot (radians, 0 = +X, clockwise-positive matching SwiftUI)
public struct StageFixturePlacement: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    /// References `PatchedFixture.id`.
    public var fixtureID: UUID
    public var x: Double
    public var y: Double
    /// Body/glyph orientation in radians.
    public var rotation: Double
    public var scale: Double
    public var labelVisible: Bool
    public var zIndex: Int
    public var locked: Bool
    public var hidden: Bool
    /// Physical beam aim on the Stage plot (radians). Independent of live DMX Pan.
    public var aimDirection: Double
    /// Full beam fan angle in radians (spread of the wedge).
    public var beamSpread: Double
    /// Visualization reach in Stage world units.
    public var beamLength: Double
    /// Whether the Stage beam visualization is drawn.
    public var beamVisible: Bool
    /// Presentation used by linear fixtures. Other fixture forms always render directionally.
    public var beamRenderMode: StageBeamRenderMode

    public init(
        id: UUID = UUID(),
        fixtureID: UUID,
        x: Double = 0,
        y: Double = 0,
        rotation: Double = 0,
        scale: Double = 1,
        labelVisible: Bool = true,
        zIndex: Int = 0,
        locked: Bool = false,
        hidden: Bool = false,
        aimDirection: Double = -.pi / 2,
        beamSpread: Double = .pi / 6,
        beamLength: Double = 160,
        beamVisible: Bool = true,
        beamRenderMode: StageBeamRenderMode = .directional
    ) {
        self.id = id
        self.fixtureID = fixtureID
        self.x = x
        self.y = y
        self.rotation = rotation
        self.scale = max(0.1, scale)
        self.labelVisible = labelVisible
        self.zIndex = zIndex
        self.locked = locked
        self.hidden = hidden
        self.aimDirection = aimDirection
        self.beamSpread = max(0.02, beamSpread)
        self.beamLength = max(8, beamLength)
        self.beamVisible = beamVisible
        self.beamRenderMode = beamRenderMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        fixtureID = try c.decode(UUID.self, forKey: .fixtureID)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        labelVisible = try c.decodeIfPresent(Bool.self, forKey: .labelVisible) ?? true
        zIndex = try c.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        // C4.1 migration defaults when fields absent
        aimDirection = try c.decodeIfPresent(Double.self, forKey: .aimDirection) ?? -.pi / 2
        beamSpread = try c.decodeIfPresent(Double.self, forKey: .beamSpread) ?? .pi / 6
        beamLength = try c.decodeIfPresent(Double.self, forKey: .beamLength) ?? 160
        beamVisible = try c.decodeIfPresent(Bool.self, forKey: .beamVisible) ?? true
        beamRenderMode = try c.decodeIfPresent(StageBeamRenderMode.self, forKey: .beamRenderMode) ?? .directional
    }

    private enum CodingKeys: String, CodingKey {
        case id, fixtureID, x, y, rotation, scale, labelVisible, zIndex, locked, hidden
        case aimDirection, beamSpread, beamLength, beamVisible, beamRenderMode
    }

    /// Category-based visualization defaults for newly placed fixtures (C4.1 §8).
    public static func beamDefaults(forCategory category: String) -> (spread: Double, length: Double) {
        let c = category.lowercased()
        if c.contains("beam") || c.contains("laser") {
            return (.pi / 24, 220) // very narrow, long
        }
        if c.contains("spot") || c.contains("profile") || c.contains("head") {
            return (.pi / 12, 200) // narrow
        }
        if c.contains("par") {
            return (.pi / 5, 150) // medium
        }
        if c.contains("wash") || c.contains("moving wash") {
            return (.pi / 3.2, 140) // broad
        }
        if c.contains("flood") {
            return (.pi / 2.4, 120) // very broad
        }
        if c.contains("bar") || c.contains("batten") || c.contains("pixel") {
            return (.pi / 2.8, 130) // fan-like
        }
        if c.contains("blinder") || c.contains("strobe") {
            return (.pi / 2.5, 100)
        }
        return (.pi / 6, 160) // generic medium
    }

    /// Factory with category-aware beam defaults.
    public static func placed(
        fixtureID: UUID,
        x: Double,
        y: Double,
        category: String = "generic"
    ) -> StageFixturePlacement {
        let d = beamDefaults(forCategory: category)
        return StageFixturePlacement(
            fixtureID: fixtureID,
            x: x,
            y: y,
            aimDirection: -.pi / 2,
            beamSpread: d.spread,
            beamLength: d.length,
            beamVisible: true
        )
    }
}

// MARK: - Legacy scenic (v1) + shape kinds

public enum StageScenicKind: String, Codable, Sendable, Hashable, CaseIterable {
    case rectangle
    case ellipse
    case label
    case region
    case stageArea
    case line
    case truss
    case roundedRectangle
    case triangle
}

/// Legacy scenic object (decoded from older shows; migrated into `StageLayoutObject`).
public struct StageScenicObject: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var kind: StageScenicKind
    public var name: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var rotation: Double
    public var zIndex: Int

    public init(
        id: UUID = UUID(),
        kind: StageScenicKind,
        name: String = "",
        x: Double = 0,
        y: Double = 0,
        width: Double = 40,
        height: Double = 40,
        rotation: Double = 0,
        zIndex: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.zIndex = zIndex
    }
}

// MARK: - Unified layout objects (C4)

public enum StageLayoutObjectKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// Geometric shape (rect, ellipse, truss-as-shape, stage area, …).
    case shape
    /// Bundled Silhouette Kit asset (`assetKey` from Catalog.json).
    case stockImage
    /// User-imported image embedded in the show package (`mediaRef`).
    case importedImage
    case text
}

/// User-editable Stage layout object (scenic, stock silhouettes, imports, text).
public struct StageLayoutObject: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var kind: StageLayoutObjectKind
    /// For `.shape` — geometric subtype.
    public var shapeKind: StageScenicKind?
    /// Stable Catalog.json key for `.stockImage` (never a filesystem path).
    public var assetKey: String?
    /// Project-relative media id for `.importedImage` (e.g. `stage/<uuid>.png`).
    public var mediaRef: String?
    public var name: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// Radians.
    public var rotation: Double
    public var zIndex: Int
    public var locked: Bool
    public var hidden: Bool
    public var opacity: Double
    /// Text content when `kind == .text`.
    public var text: String

    public init(
        id: UUID = UUID(),
        kind: StageLayoutObjectKind,
        shapeKind: StageScenicKind? = nil,
        assetKey: String? = nil,
        mediaRef: String? = nil,
        name: String = "",
        x: Double = 0,
        y: Double = 0,
        width: Double = 80,
        height: Double = 120,
        rotation: Double = 0,
        zIndex: Int = 0,
        locked: Bool = false,
        hidden: Bool = false,
        opacity: Double = 0.9,
        text: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.shapeKind = shapeKind
        self.assetKey = assetKey
        self.mediaRef = mediaRef
        self.name = name
        self.x = x
        self.y = y
        self.width = max(4, width)
        self.height = max(4, height)
        self.rotation = rotation
        self.zIndex = zIndex
        self.locked = locked
        self.hidden = hidden
        self.opacity = min(1, max(0, opacity))
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(StageLayoutObjectKind.self, forKey: .kind)
        shapeKind = try c.decodeIfPresent(StageScenicKind.self, forKey: .shapeKind)
        assetKey = try c.decodeIfPresent(String.self, forKey: .assetKey)
        mediaRef = try c.decodeIfPresent(String.self, forKey: .mediaRef)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 80
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 120
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        zIndex = try c.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.9
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, shapeKind, assetKey, mediaRef, name
        case x, y, width, height, rotation, zIndex, locked, hidden, opacity, text
    }

    public static func fromLegacyScenic(_ s: StageScenicObject) -> StageLayoutObject {
        StageLayoutObject(
            id: s.id,
            kind: .shape,
            shapeKind: s.kind,
            name: s.name,
            x: s.x,
            y: s.y,
            width: s.width,
            height: s.height,
            rotation: s.rotation,
            zIndex: s.zIndex,
            locked: false,
            hidden: false,
            opacity: 1
        )
    }

    public static func stock(
        assetKey: String,
        name: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        opacity: Double = 0.9,
        zIndex: Int = 0
    ) -> StageLayoutObject {
        StageLayoutObject(
            kind: .stockImage,
            assetKey: assetKey,
            name: name,
            x: x,
            y: y,
            width: width,
            height: height,
            zIndex: zIndex,
            opacity: opacity
        )
    }

    public static func shape(
        _ shapeKind: StageScenicKind,
        name: String = "",
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        zIndex: Int = 0
    ) -> StageLayoutObject {
        StageLayoutObject(
            kind: .shape,
            shapeKind: shapeKind,
            name: name.isEmpty ? shapeKind.rawValue : name,
            x: x,
            y: y,
            width: width,
            height: height,
            zIndex: zIndex,
            opacity: 1
        )
    }
}

// MARK: - Stage layout

/// Full stage canvas configuration persisted with the show.
public struct StageLayout: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var canvasWidth: Double
    public var canvasHeight: Double
    public var gridSize: Double
    public var snapToGrid: Bool
    public var fixtures: [StageFixturePlacement]
    /// Unified C4 layout objects (shapes, stock silhouettes, imports, text).
    public var objects: [StageLayoutObject]
    /// Legacy field — kept for encode compatibility; prefer `objects`.
    public var scenic: [StageScenicObject]

    public static let currentSchemaVersion = 2

    public init(
        schemaVersion: Int = StageLayout.currentSchemaVersion,
        canvasWidth: Double = 1200,
        canvasHeight: Double = 800,
        gridSize: Double = 20,
        snapToGrid: Bool = true,
        fixtures: [StageFixturePlacement] = [],
        objects: [StageLayoutObject] = [],
        scenic: [StageScenicObject] = []
    ) {
        self.schemaVersion = schemaVersion
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.gridSize = gridSize
        self.snapToGrid = snapToGrid
        self.fixtures = fixtures
        self.objects = objects
        self.scenic = scenic
        if self.objects.isEmpty, !self.scenic.isEmpty {
            self.objects = self.scenic.map(StageLayoutObject.fromLegacyScenic)
        }
    }

    public static let empty = StageLayout()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        canvasWidth = try c.decodeIfPresent(Double.self, forKey: .canvasWidth) ?? 1200
        canvasHeight = try c.decodeIfPresent(Double.self, forKey: .canvasHeight) ?? 800
        gridSize = try c.decodeIfPresent(Double.self, forKey: .gridSize) ?? 20
        snapToGrid = try c.decodeIfPresent(Bool.self, forKey: .snapToGrid) ?? true
        fixtures = try c.decodeIfPresent([StageFixturePlacement].self, forKey: .fixtures) ?? []
        objects = try c.decodeIfPresent([StageLayoutObject].self, forKey: .objects) ?? []
        scenic = try c.decodeIfPresent([StageScenicObject].self, forKey: .scenic) ?? []
        if objects.isEmpty, !scenic.isEmpty {
            objects = scenic.map(StageLayoutObject.fromLegacyScenic)
        }
        schemaVersion = max(schemaVersion, 2)
        // Keep scenic mirror for older readers during transition.
        scenic = objects.compactMap { obj -> StageScenicObject? in
            guard obj.kind == .shape, let sk = obj.shapeKind else { return nil }
            return StageScenicObject(
                id: obj.id, kind: sk, name: obj.name,
                x: obj.x, y: obj.y, width: obj.width, height: obj.height,
                rotation: obj.rotation, zIndex: obj.zIndex
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(canvasWidth, forKey: .canvasWidth)
        try c.encode(canvasHeight, forKey: .canvasHeight)
        try c.encode(gridSize, forKey: .gridSize)
        try c.encode(snapToGrid, forKey: .snapToGrid)
        try c.encode(fixtures, forKey: .fixtures)
        try c.encode(objects, forKey: .objects)
        // Mirror shapes into scenic for backward compatibility.
        let legacy = objects.compactMap { obj -> StageScenicObject? in
            guard obj.kind == .shape, let sk = obj.shapeKind else { return nil }
            return StageScenicObject(
                id: obj.id, kind: sk, name: obj.name,
                x: obj.x, y: obj.y, width: obj.width, height: obj.height,
                rotation: obj.rotation, zIndex: obj.zIndex
            )
        }
        try c.encode(legacy, forKey: .scenic)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, canvasWidth, canvasHeight, gridSize, snapToGrid
        case fixtures, objects, scenic
    }

    /// Next z-index above all current objects and fixtures.
    public var nextZIndex: Int {
        let oz = objects.map(\.zIndex).max() ?? 0
        let fz = fixtures.map(\.zIndex).max() ?? 0
        return max(oz, fz) + 1
    }

    public mutating func appendObject(_ obj: StageLayoutObject) {
        var o = obj
        if o.zIndex == 0 { o.zIndex = nextZIndex }
        objects.append(o)
    }

    public func object(id: UUID) -> StageLayoutObject? {
        objects.first { $0.id == id }
    }

    public mutating func updateObject(_ obj: StageLayoutObject) {
        if let i = objects.firstIndex(where: { $0.id == obj.id }) {
            objects[i] = obj
        }
    }
}
