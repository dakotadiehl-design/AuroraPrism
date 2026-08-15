import AuroraModel
import CoreGraphics
import Foundation

// MARK: - Transform ownership (C4.2)

/// Authoritative answer to “what transform currently owns this pointer?”
/// A single drag must never simultaneously move + resize + aim + rotate + pan.
public enum StageTransformInteraction: Equatable, Sendable {
    case none
    case move(objectID: UUID)
    /// Corner detail lives in `StageObjectResizeState`; ownership only needs the object id.
    case resize(objectID: UUID)
    case rotate(objectID: UUID)
    case aim(fixtureID: UUID)
    case pan

    public var isNone: Bool {
        if case .none = self { return true }
        return false
    }

    public var blocksMove: Bool {
        switch self {
        case .none: return false
        case .move: return false
        case .resize, .rotate, .aim, .pan: return true
        }
    }

    public var blocksResize: Bool {
        switch self {
        case .none, .resize: return false
        default: return true
        }
    }

    public var blocksAim: Bool {
        switch self {
        case .none, .aim: return false
        default: return true
        }
    }

    public var blocksRotate: Bool {
        switch self {
        case .none, .rotate: return false
        default: return true
        }
    }
}

// MARK: - Direct beam aim math (C4.2)

/// Pure aim geometry: pointer relative to fixture center → direction + length.
public enum StageAimMath {
    /// - Parameters:
    ///   - fixtureCenter: Stage world position of the fixture.
    ///   - pointer: Stage world position of the aim handle / pointer.
    /// - Returns: `(aimDirection radians, beamLength)` using Aurora’s atan2 convention
    ///   (0 = +X, positive clockwise in y-down Stage coordinates — same as `atan2(dy, dx)`).
    public static func aimFromPointer(
        fixtureCenter: CGPoint,
        pointer: CGPoint
    ) -> (direction: Double, length: Double) {
        let dx = Double(pointer.x - fixtureCenter.x)
        let dy = Double(pointer.y - fixtureCenter.y)
        let length = max(8, hypot(dx, dy))
        let direction = atan2(dy, dx)
        return (direction, length)
    }

    /// World position of the aim handle on the beam centerline.
    public static func handlePoint(
        fixtureCenter: CGPoint,
        direction: Double,
        length: Double
    ) -> CGPoint {
        let len = max(8, length)
        return CGPoint(
            x: fixtureCenter.x + CGFloat(cos(direction) * len),
            y: fixtureCenter.y + CGFloat(sin(direction) * len)
        )
    }
}

/// Transient fixture aim drag (physical Stage aim — not DMX Pan).
public struct StageFixtureAimState: Equatable, Sendable {
    public var fixtureID: UUID
    public var originalDirection: Double
    public var originalLength: Double
    public var currentDirection: Double
    public var currentLength: Double

    public init(
        fixtureID: UUID,
        originalDirection: Double,
        originalLength: Double,
        currentDirection: Double? = nil,
        currentLength: Double? = nil
    ) {
        self.fixtureID = fixtureID
        self.originalDirection = originalDirection
        self.originalLength = originalLength
        self.currentDirection = currentDirection ?? originalDirection
        self.currentLength = currentLength ?? originalLength
    }
}

// MARK: - Direct object rotation math (C4.2)

public enum StageRotateMath {
    /// Rotation from pointer around object center (radians).
    public static func rotationFromPointer(
        center: CGPoint,
        pointer: CGPoint,
        orientationOffset: Double = 0
    ) -> Double {
        let dx = Double(pointer.x - center.x)
        let dy = Double(pointer.y - center.y)
        return atan2(dy, dx) + orientationOffset
    }

    /// Default rotation-handle offset above object (local +Y negative in y-down = up on screen when unrotated).
    public static func handleOffset(objectHeight: Double, margin: Double = 22) -> CGPoint {
        CGPoint(x: 0, y: -CGFloat(objectHeight * 0.5 + margin))
    }
}

public struct StageObjectRotateState: Equatable, Sendable {
    public var objectID: UUID
    public var originalRotation: Double
    public var currentRotation: Double
    /// Offset so initial drag doesn't jump (handle angle − object rotation at start).
    public var orientationOffset: Double

    public init(
        objectID: UUID,
        originalRotation: Double,
        currentRotation: Double? = nil,
        orientationOffset: Double = 0
    ) {
        self.objectID = objectID
        self.originalRotation = originalRotation
        self.currentRotation = currentRotation ?? originalRotation
        self.orientationOffset = orientationOffset
    }
}

// MARK: - Camera pan (C3.1)

/// Pure camera pan math — origin + gesture translation (never compound translation into itself).
public enum StageCameraPan {
    /// Displayed/final pan for a drag that started at `start` with cumulative `translation` from gesture start.
    public static func displayedPan(start: CGSize, translation: CGSize) -> CGSize {
        CGSize(width: start.width + translation.width, height: start.height + translation.height)
    }
}

// MARK: - World-space object drag (C3.1 fixtures; reusable for C4 layout objects)

/// Transient multi-object drag in Stage world coordinates.
/// IDs may be fixture IDs today; C4 can reuse the same delta model for scenic objects.
public struct StageObjectDragState: Equatable, Sendable {
    public var anchorID: UUID
    /// Committed world positions at drag start (movable objects only).
    public var originalPositions: [UUID: CGPoint]
    /// Current world-space delta (after zoom conversion; optionally grid-snapped).
    public var currentDelta: CGSize

    public init(
        anchorID: UUID,
        originalPositions: [UUID: CGPoint],
        currentDelta: CGSize = .zero
    ) {
        self.anchorID = anchorID
        self.originalPositions = originalPositions
        self.currentDelta = currentDelta
    }

    public var movableIDs: Set<UUID> { Set(originalPositions.keys) }

    /// Live display position during drag.
    public func displayPosition(for id: UUID) -> CGPoint? {
        guard let origin = originalPositions[id] else { return nil }
        return CGPoint(
            x: origin.x + currentDelta.width,
            y: origin.y + currentDelta.height
        )
    }
}

/// Fixture-drag alias for existing call sites (same storage as `StageObjectDragState`).
public typealias StageFixtureDragState = StageObjectDragState

public extension StageObjectDragState {
    /// Back-compat accessors for fixture-specific naming.
    var anchorFixtureID: UUID {
        get { anchorID }
        set { anchorID = newValue }
    }

    init(
        anchorFixtureID: UUID,
        originalPositions: [UUID: CGPoint],
        currentDelta: CGSize = .zero
    ) {
        self.init(anchorID: anchorFixtureID, originalPositions: originalPositions, currentDelta: currentDelta)
    }
}

/// View ↔ Stage world drag math (fixtures today; scenic objects in C4).
public enum StageWorldDragMath {
    /// Convert pointer translation in view pixels into Stage world delta.
    /// `scale` is the camera zoom applied to the Stage world (`scaleEffect`).
    public static func worldDelta(viewTranslation: CGSize, scale: CGFloat) -> CGSize {
        let s = max(scale, 0.0001)
        return CGSize(
            width: viewTranslation.width / s,
            height: viewTranslation.height / s
        )
    }

    /// Snap a world-space delta so the **anchor** ends on grid; apply same delta to whole group.
    public static func snapDelta(
        _ delta: CGSize,
        anchorOrigin: CGPoint,
        gridSize: Double,
        snapToGrid: Bool
    ) -> CGSize {
        guard snapToGrid, gridSize > 0 else { return delta }
        let targetX = anchorOrigin.x + Double(delta.width)
        let targetY = anchorOrigin.y + Double(delta.height)
        let snappedX = (targetX / gridSize).rounded() * gridSize
        let snappedY = (targetY / gridSize).rounded() * gridSize
        return CGSize(
            width: snappedX - anchorOrigin.x,
            height: snappedY - anchorOrigin.y
        )
    }

    /// Final world positions after applying delta to originals.
    public static func finalPositions(
        originals: [UUID: CGPoint],
        delta: CGSize
    ) -> [UUID: CGPoint] {
        var out: [UUID: CGPoint] = [:]
        out.reserveCapacity(originals.count)
        for (id, origin) in originals {
            out[id] = CGPoint(x: origin.x + delta.width, y: origin.y + delta.height)
        }
        return out
    }

    /// Compute snapped world delta from a drag gesture (production completion path).
    public static func resolvedDelta(
        viewTranslation: CGSize,
        scale: CGFloat,
        anchorOrigin: CGPoint,
        gridSize: Double,
        snapToGrid: Bool
    ) -> CGSize {
        let raw = worldDelta(viewTranslation: viewTranslation, scale: scale)
        return snapDelta(raw, anchorOrigin: anchorOrigin, gridSize: gridSize, snapToGrid: snapToGrid)
    }
}

/// Fixture-named alias — same math as `StageWorldDragMath`.
public typealias StageFixtureDragMath = StageWorldDragMath

// MARK: - Production drag finalization (testable path used by StageCanvasView)

/// Applies a completed object drag to a Stage layout. One logical document mutation input.
public enum StageLayoutDragFinalizer {
    /// Capture movable fixture origins for a multi-select drag (skips locked/hidden).
    public static func fixtureOrigins(
        layout: StageLayout,
        selection: Set<UUID>,
        anchorID: UUID
    ) -> [UUID: CGPoint] {
        var origins: [UUID: CGPoint] = [:]
        for place in layout.fixtures {
            guard selection.contains(place.fixtureID) || place.fixtureID == anchorID else { continue }
            guard !place.locked, !place.hidden else { continue }
            origins[place.fixtureID] = CGPoint(x: place.x, y: place.y)
        }
        return origins
    }

    /// Capture movable layout-object origins (stock/scenic/import). Selection uses object `id`.
    public static func objectOrigins(
        layout: StageLayout,
        selection: Set<UUID>,
        anchorID: UUID
    ) -> [UUID: CGPoint] {
        var origins: [UUID: CGPoint] = [:]
        for obj in layout.objects {
            guard selection.contains(obj.id) || obj.id == anchorID else { continue }
            guard !obj.locked, !obj.hidden else { continue }
            origins[obj.id] = CGPoint(x: obj.x, y: obj.y)
        }
        return origins
    }

    /// Build the final layout from committed layout + drag state + final view translation.
    /// Moves both fixtures (by fixtureID) and layout objects (by object id).
    /// Returns `nil` if nothing moved (no document mutation required).
    public static func finalizedLayout(
        layout: StageLayout,
        drag: StageObjectDragState,
        viewTranslation: CGSize,
        scale: CGFloat
    ) -> StageLayout? {
        guard let anchorOrigin = drag.originalPositions[drag.anchorID] else { return nil }
        let delta = StageWorldDragMath.resolvedDelta(
            viewTranslation: viewTranslation,
            scale: scale,
            anchorOrigin: anchorOrigin,
            gridSize: layout.gridSize,
            snapToGrid: layout.snapToGrid
        )
        let finals = StageWorldDragMath.finalPositions(originals: drag.originalPositions, delta: delta)
        var next = layout
        var moved = false
        for i in next.fixtures.indices {
            let id = next.fixtures[i].fixtureID
            guard let p = finals[id], !next.fixtures[i].locked else { continue }
            if next.fixtures[i].x != p.x || next.fixtures[i].y != p.y {
                next.fixtures[i].x = p.x
                next.fixtures[i].y = p.y
                moved = true
            }
        }
        for i in next.objects.indices {
            let id = next.objects[i].id
            guard let p = finals[id], !next.objects[i].locked else { continue }
            if next.objects[i].x != p.x || next.objects[i].y != p.y {
                next.objects[i].x = p.x
                next.objects[i].y = p.y
                moved = true
            }
        }
        return moved ? next : nil
    }

    /// Preview world delta for live rendering (same snap rules as commit).
    public static func liveDelta(
        layout: StageLayout,
        drag: StageObjectDragState,
        viewTranslation: CGSize,
        scale: CGFloat
    ) -> CGSize {
        guard let anchorOrigin = drag.originalPositions[drag.anchorID] else { return .zero }
        return StageWorldDragMath.resolvedDelta(
            viewTranslation: viewTranslation,
            scale: scale,
            anchorOrigin: anchorOrigin,
            gridSize: layout.gridSize,
            snapToGrid: layout.snapToGrid
        )
    }
}

// MARK: - Layout object resize (C4A / C4.1)

/// Corner used for interactive resize (local object axes; opposite corner stays fixed).
public enum StageResizeCorner: String, Sendable, Hashable, CaseIterable {
    case northWest
    case northEast
    case southWest
    case southEast

    /// Local-space unit vector for how positive world-delta (in local axes) grows width/height.
    /// NW: drag left/up grows; SE: drag right/down grows.
    public var widthSign: Double {
        switch self {
        case .northEast, .southEast: return 1
        case .northWest, .southWest: return -1
        }
    }

    public var heightSign: Double {
        switch self {
        case .southWest, .southEast: return 1
        case .northWest, .northEast: return -1
        }
    }
}

/// Kind of object for aspect-ratio policy.
public enum StageResizeAspectPolicy: String, Sendable, Hashable {
    /// Stock silhouettes, imported images, truss-as-image — preserve aspect by default.
    case preserveByDefault
    /// Free geometric shapes — free by default.
    case freeByDefault

    /// Whether to lock aspect for the current modifier state.
    public func lockAspect(shiftHeld: Bool) -> Bool {
        switch self {
        case .preserveByDefault: return !shiftHeld
        case .freeByDefault: return shiftHeld
        }
    }

    public static func policy(for kind: StageLayoutObjectKind, shapeKind: StageScenicKind?) -> StageResizeAspectPolicy {
        switch kind {
        case .stockImage, .importedImage:
            return .preserveByDefault
        case .text:
            return .freeByDefault
        case .shape:
            if shapeKind == .truss || shapeKind == .line {
                return .preserveByDefault
            }
            return .freeByDefault
        }
    }
}

/// Transient resize of one unlocked layout object.
public struct StageObjectResizeState: Equatable, Sendable {
    public var objectID: UUID
    public var corner: StageResizeCorner
    public var originalX: Double
    public var originalY: Double
    public var originalWidth: Double
    public var originalHeight: Double
    public var originalRotation: Double
    public var aspectPolicy: StageResizeAspectPolicy
    public var currentX: Double
    public var currentY: Double
    public var currentWidth: Double
    public var currentHeight: Double

    public init(
        objectID: UUID,
        corner: StageResizeCorner = .southEast,
        originalX: Double,
        originalY: Double,
        originalWidth: Double,
        originalHeight: Double,
        originalRotation: Double = 0,
        aspectPolicy: StageResizeAspectPolicy = .freeByDefault,
        currentX: Double? = nil,
        currentY: Double? = nil,
        currentWidth: Double? = nil,
        currentHeight: Double? = nil
    ) {
        self.objectID = objectID
        self.corner = corner
        self.originalX = originalX
        self.originalY = originalY
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.originalRotation = originalRotation
        self.aspectPolicy = aspectPolicy
        self.currentX = currentX ?? originalX
        self.currentY = currentY ?? originalY
        self.currentWidth = currentWidth ?? originalWidth
        self.currentHeight = currentHeight ?? originalHeight
    }
}

/// Pure resize math — live preview + one-commit finalization (C4.1 multi-corner).
public enum StageLayoutResizeFinalizer {
    public static let minSize: Double = 8

    /// Result of a resize sample: center + size in Stage world.
    public struct Geometry: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// Compute new geometry for a corner drag.
    /// - Parameter translationIsLocal: When `true`, `viewTranslation` is already in the object's
    ///   local axes (gesture attached inside `rotationEffect`). When `false` (default), translation
    ///   is in Stage/world view pixels and is unrotated into local axes first.
    public static func geometry(
        resize: StageObjectResizeState,
        viewTranslation: CGSize,
        scale: CGFloat,
        shiftHeld: Bool,
        translationIsLocal: Bool = false
    ) -> Geometry {
        let scaled = StageWorldDragMath.worldDelta(viewTranslation: viewTranslation, scale: scale)
        let localDX: Double
        let localDY: Double
        if translationIsLocal {
            localDX = Double(scaled.width)
            localDY = Double(scaled.height)
        } else {
            // Unrotate translation into object-local axes.
            let cosR = cos(-resize.originalRotation)
            let sinR = sin(-resize.originalRotation)
            localDX = Double(scaled.width) * cosR - Double(scaled.height) * sinR
            localDY = Double(scaled.width) * sinR + Double(scaled.height) * cosR
        }

        var newW = resize.originalWidth + localDX * resize.corner.widthSign
        var newH = resize.originalHeight + localDY * resize.corner.heightSign

        let lockAspect = resize.aspectPolicy.lockAspect(shiftHeld: shiftHeld)
        if lockAspect, resize.originalWidth > 0.001, resize.originalHeight > 0.001 {
            let aspect = resize.originalWidth / resize.originalHeight
            // Dominant axis by absolute local growth magnitude
            if abs(localDX) >= abs(localDY) {
                newW = max(minSize, newW)
                newH = max(minSize, newW / aspect)
            } else {
                newH = max(minSize, newH)
                newW = max(minSize, newH * aspect)
            }
        } else {
            newW = max(minSize, newW)
            newH = max(minSize, newH)
        }

        // Keep opposite corner fixed: center shifts by half the size delta in local axes.
        let dW = newW - resize.originalWidth
        let dH = newH - resize.originalHeight
        // Moving SE grows right/down → center moves +dW/2, +dH/2 in local
        // Moving NW grows left/up → local signs invert via corner signs already in dW/dH definition
        let localCenterDX = dW * 0.5 * resize.corner.widthSign
        let localCenterDY = dH * 0.5 * resize.corner.heightSign
        // Rotate local center delta back to world
        let cosF = cos(resize.originalRotation)
        let sinF = sin(resize.originalRotation)
        let worldDX = localCenterDX * cosF - localCenterDY * sinF
        let worldDY = localCenterDX * sinF + localCenterDY * cosF

        return Geometry(
            x: resize.originalX + worldDX,
            y: resize.originalY + worldDY,
            width: newW,
            height: newH
        )
    }

    /// Apply completed resize to layout. Returns `nil` if object missing, locked, or unchanged.
    public static func finalizedLayout(
        layout: StageLayout,
        resize: StageObjectResizeState,
        viewTranslation: CGSize,
        scale: CGFloat,
        shiftHeld: Bool = false,
        translationIsLocal: Bool = false
    ) -> StageLayout? {
        guard let idx = layout.objects.firstIndex(where: { $0.id == resize.objectID }) else { return nil }
        guard !layout.objects[idx].locked else { return nil }
        let g = geometry(
            resize: resize,
            viewTranslation: viewTranslation,
            scale: scale,
            shiftHeld: shiftHeld,
            translationIsLocal: translationIsLocal
        )
        var next = layout
        if abs(next.objects[idx].width - g.width) < 0.001,
           abs(next.objects[idx].height - g.height) < 0.001,
           abs(next.objects[idx].x - g.x) < 0.001,
           abs(next.objects[idx].y - g.y) < 0.001 {
            return nil
        }
        next.objects[idx].x = g.x
        next.objects[idx].y = g.y
        next.objects[idx].width = g.width
        next.objects[idx].height = g.height
        return next
    }

    /// Live display geometry during resize gesture.
    public static func liveGeometry(
        resize: StageObjectResizeState,
        viewTranslation: CGSize,
        scale: CGFloat,
        shiftHeld: Bool = false,
        translationIsLocal: Bool = false
    ) -> Geometry {
        geometry(
            resize: resize,
            viewTranslation: viewTranslation,
            scale: scale,
            shiftHeld: shiftHeld,
            translationIsLocal: translationIsLocal
        )
    }

    // MARK: Back-compat helpers (C4 SE-only API)

    public static func sizeForSouthEast(
        originalWidth: Double,
        originalHeight: Double,
        viewTranslation: CGSize,
        scale: CGFloat
    ) -> (width: Double, height: Double) {
        let resize = StageObjectResizeState(
            objectID: UUID(),
            corner: .southEast,
            originalX: 0, originalY: 0,
            originalWidth: originalWidth,
            originalHeight: originalHeight
        )
        let g = geometry(resize: resize, viewTranslation: viewTranslation, scale: scale, shiftHeld: false)
        return (g.width, g.height)
    }

    public static func liveSize(
        resize: StageObjectResizeState,
        viewTranslation: CGSize,
        scale: CGFloat
    ) -> CGSize {
        let g = liveGeometry(resize: resize, viewTranslation: viewTranslation, scale: scale, shiftHeld: false)
        return CGSize(width: g.width, height: g.height)
    }
}
