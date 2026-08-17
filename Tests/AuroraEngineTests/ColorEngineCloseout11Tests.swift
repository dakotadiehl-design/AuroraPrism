import AuroraEngine
import AuroraModel
import XCTest

/// C.E. 1.1 closeout: geometry, virtual dimmer, global master safety, palette keys.
final class ColorEngineCloseout11Tests: XCTestCase {

    // MARK: - Saturation annulus geometry

    func testSaturationAnnulusEndpoints() {
        let inner = 50.0
        let outer = 100.0
        XCTAssertEqual(
            ColorMath.saturationInAnnulus(pointerRadius: inner, innerSatRadius: inner, outerSatRadius: outer),
            0,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ColorMath.saturationInAnnulus(pointerRadius: (inner + outer) / 2, innerSatRadius: inner, outerSatRadius: outer),
            0.5,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ColorMath.saturationInAnnulus(pointerRadius: outer, innerSatRadius: inner, outerSatRadius: outer),
            1,
            accuracy: 0.01
        )
    }

    func testSaturationThumbRoundTrip() {
        let inner = 40.0
        let outer = 90.0
        for sat in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let r = ColorMath.saturationThumbRadius(saturation: sat, innerSatRadius: inner, outerSatRadius: outer)
            let back = ColorMath.saturationInAnnulus(pointerRadius: r, innerSatRadius: inner, outerSatRadius: outer)
            XCTAssertEqual(back, sat, accuracy: 0.02, "sat \(sat)")
        }
    }

    // MARK: - White balance geometry

    func testWhiteBalanceAngleEndpoints() {
        let cool = ColorMath.whiteBalanceAngleDegrees(-1)
        let neutral = ColorMath.whiteBalanceAngleDegrees(0)
        let warm = ColorMath.whiteBalanceAngleDegrees(1)
        XCTAssertEqual(ColorMath.whiteBalance(fromAngleDegrees: cool), -1, accuracy: 0.05)
        XCTAssertEqual(ColorMath.whiteBalance(fromAngleDegrees: neutral), 0, accuracy: 0.05)
        XCTAssertEqual(ColorMath.whiteBalance(fromAngleDegrees: warm), 1, accuracy: 0.05)
        // Cool and warm on opposite sides of left arc
        XCTAssertNotEqual(cool, warm, accuracy: 1)
    }

    func testWhiteBalanceRoundTrip() {
        for w in [-1.0, -0.5, 0.0, 0.5, 1.0] {
            let angle = ColorMath.whiteBalanceAngleDegrees(w)
            let back = ColorMath.whiteBalance(fromAngleDegrees: angle)
            XCTAssertEqual(back, w, accuracy: 0.08, "w=\(w)")
        }
    }

    func testWhiteBalanceNeutralHasMouseDetent() {
        XCTAssertEqual(ColorMath.whiteBalance(fromAngleDegrees: 180), 0, accuracy: 0.0001)
        XCTAssertEqual(ColorMath.whiteBalance(fromAngleDegrees: 174), 0, accuracy: 0.0001)
        XCTAssertEqual(ColorMath.whiteBalance(fromAngleDegrees: -174), 0, accuracy: 0.0001)
        XCTAssertNotEqual(ColorMath.whiteBalance(fromAngleDegrees: 168), 0, accuracy: 0.0001)
    }

    func testBrightnessBottomDetentIsLiteralOff() {
        XCTAssertEqual(ColorMath.brightness(fromAngleDegrees: 90), 0, accuracy: 0.0001)
        XCTAssertEqual(ColorMath.brightness(fromAngleDegrees: 84), 0, accuracy: 0.0001)
        XCTAssertNotEqual(ColorMath.brightness(fromAngleDegrees: 78), 0, accuracy: 0.0001)

        let rgb = ColorMath.resolvedRGB(
            hue: 210,
            saturation: 0.8,
            brightness: ColorMath.brightness(fromAngleDegrees: 84),
            whiteBalance: 0.5
        )
        XCTAssertEqual(rgb, RGBColor(r: 0, g: 0, b: 0))
    }

    // MARK: - Global master leaves authoring alone

    func testGlobalMasterDoesNotScaleAuthoringKeys() {
        var look = ActiveLook()
        let id = UUID()
        look.fixtureAttributes[id] = [
            ColorAuthoringAttribute.hue: 120,
            ColorAuthoringAttribute.saturation: 0.7,
            ColorAuthoringAttribute.brightness: 0.8,
            ColorAuthoringAttribute.whiteBalance: 0.2,
            "colorR": 1,
            "colorG": 0.5,
            "colorB": 0,
        ]
        let state = GlobalShowControlState(masterIntensity: 0.5)
        let scaled = GlobalShowControl.applyToLook(look, state: state)
        let attrs = scaled.fixtureAttributes[id]!
        XCTAssertEqual(attrs[ColorAuthoringAttribute.hue]!, 120, accuracy: 0.001)
        XCTAssertEqual(attrs[ColorAuthoringAttribute.saturation]!, 0.7, accuracy: 0.001)
        XCTAssertEqual(attrs[ColorAuthoringAttribute.brightness]!, 0.8, accuracy: 0.001)
        XCTAssertEqual(attrs[ColorAuthoringAttribute.whiteBalance]!, 0.2, accuracy: 0.001)
        // Physical RGB scales when no dimmer present
        XCTAssertEqual(attrs["colorR"]!, 0.5, accuracy: 0.01)
    }

    func testBlackoutDoesNotClearAuthoringKeys() {
        var look = ActiveLook()
        let id = UUID()
        look.fixtureAttributes[id] = [
            ColorAuthoringAttribute.hue: 40,
            "colorR": 1,
        ]
        let state = GlobalShowControlState(blackout: true)
        let scaled = GlobalShowControl.applyToLook(look, state: state)
        XCTAssertEqual(scaled.fixtureAttributes[id]![ColorAuthoringAttribute.hue]!, 40, accuracy: 0.001)
        XCTAssertEqual(scaled.fixtureAttributes[id]!["colorR"]!, 0, accuracy: 0.001)
    }

    // MARK: - Virtual dimmer

    func testVirtualDimmerScalesRGBEmittersAtOutput() {
        let def = FixtureDefinition(
            manufacturer: "T",
            model: "RGB",
            channels: [
                ChannelDef(offset: 1, name: "R", attribute: "colorR"),
                ChannelDef(offset: 2, name: "G", attribute: "colorG"),
                ChannelDef(offset: 3, name: "B", attribute: "colorB"),
            ]
        )
        let writes = CompiledShow.compileAttributeWrites(definition: def)
        let fixture = CompiledFixture(
            id: UUID(),
            universeNumber: 1,
            baseAddress: 1,
            definitionId: def.id,
            attributeWrites: writes
        )
        let attrs: [String: Double] = [
            "colorR": 1, "colorG": 0.5, "colorB": 0,
            "intensity": 0.4,
            ColorAuthoringAttribute.hue: 30,
        ]
        let resolved = MergeStub.resolveOutputAttributes(attrs, for: fixture)
        XCTAssertEqual(resolved["colorR"]!, 0.4, accuracy: 0.01)
        XCTAssertEqual(resolved["colorG"]!, 0.2, accuracy: 0.01)
        XCTAssertEqual(resolved["colorB"]!, 0, accuracy: 0.01)
        // Authoring unchanged
        XCTAssertEqual(resolved[ColorAuthoringAttribute.hue]!, 30, accuracy: 0.01)
    }

    func testPhysicalDimmerDoesNotScaleEmittersInResolve() {
        let def = FixtureDefinition(
            manufacturer: "T",
            model: "RGBD",
            channels: [
                ChannelDef(offset: 1, name: "Dim", attribute: "intensity"),
                ChannelDef(offset: 2, name: "R", attribute: "colorR"),
                ChannelDef(offset: 3, name: "G", attribute: "colorG"),
                ChannelDef(offset: 4, name: "B", attribute: "colorB"),
            ]
        )
        let writes = CompiledShow.compileAttributeWrites(definition: def)
        let fixture = CompiledFixture(
            id: UUID(),
            universeNumber: 1,
            baseAddress: 1,
            definitionId: def.id,
            attributeWrites: writes
        )
        let attrs: [String: Double] = ["colorR": 1, "colorG": 0.5, "intensity": 0.4]
        let resolved = MergeStub.resolveOutputAttributes(attrs, for: fixture)
        XCTAssertEqual(resolved["colorR"]!, 1, accuracy: 0.01)
        XCTAssertEqual(resolved["intensity"]!, 0.4, accuracy: 0.01)
    }

    func testVirtualDimmerScalesAllDedicatedEmitters() {
        let def = FixtureDefinition(
            manufacturer: "T",
            model: "RGBWAUV",
            channels: [
                ChannelDef(offset: 1, name: "R", attribute: "colorR"),
                ChannelDef(offset: 2, name: "G", attribute: "colorG"),
                ChannelDef(offset: 3, name: "B", attribute: "colorB"),
                ChannelDef(offset: 4, name: "W", attribute: "colorW"),
                ChannelDef(offset: 5, name: "A", attribute: "colorA"),
                ChannelDef(offset: 6, name: "UV", attribute: "colorUV"),
            ]
        )
        let writes = CompiledShow.compileAttributeWrites(definition: def)
        let fixture = CompiledFixture(
            id: UUID(),
            universeNumber: 1,
            baseAddress: 1,
            definitionId: def.id,
            attributeWrites: writes
        )
        let attrs: [String: Double] = [
            "colorR": 0.8, "colorW": 0.4, "colorA": 0.2, "colorUV": 0.6,
            "intensity": 0.5,
        ]
        let resolved = MergeStub.resolveOutputAttributes(attrs, for: fixture)
        XCTAssertEqual(resolved["colorR"]!, 0.4, accuracy: 0.01)
        XCTAssertEqual(resolved["colorW"]!, 0.2, accuracy: 0.01)
        XCTAssertEqual(resolved["colorA"]!, 0.1, accuracy: 0.01)
        XCTAssertEqual(resolved["colorUV"]!, 0.3, accuracy: 0.01)
    }

    func testIsColorEmitterExcludesAuthoring() {
        XCTAssertFalse(GlobalShowControl.isColorEmitter(ColorAuthoringAttribute.hue))
        XCTAssertFalse(GlobalShowControl.isColorEmitter(ColorAuthoringAttribute.whiteBalance))
        XCTAssertTrue(GlobalShowControl.isColorEmitter("colorR"))
        XCTAssertTrue(GlobalShowControl.isColorEmitter("colorUV"))
    }

    // MARK: - Pass 2 final: effective intensity + defaults

    private func rgbOnlyProject() -> (ShowProject, UUID) {
        var project = ShowProject.empty(name: "RGB")
        let defID = UUID()
        let uni = UUID()
        let fx = UUID()
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: defID, manufacturer: "T", model: "RGB",
                channels: [
                    ChannelDef(offset: 1, name: "R", attribute: "colorR"),
                    ChannelDef(offset: 2, name: "G", attribute: "colorG"),
                    ChannelDef(offset: 3, name: "B", attribute: "colorB"),
                ]
            )
        ]
        project.universes = [Universe(id: uni, number: 1, channelCount: 512)]
        project.fixtures = [
            PatchedFixture(id: fx, name: "PAR", definitionId: defID, universeId: uni, address: 1)
        ]
        return (project, fx)
    }

    func testEffectiveIntensityCapabilityForRGBOnly() {
        let (project, fx) = rgbOnlyProject()
        let physical = ProgrammerAttributePresentationResolver.physicalCapabilityMap(
            orderedFixtureIDs: [fx], project: project
        )
        XCTAssertFalse(physical[fx]!.contains("intensity"))
        XCTAssertEqual(
            ProgrammerAttributePresentationResolver.effectiveIntensityMode(physicalCaps: physical[fx]!),
            .virtualEmitterScale
        )
        let effective = ProgrammerAttributePresentationResolver.capabilityMap(
            orderedFixtureIDs: [fx], project: project
        )
        XCTAssertTrue(effective[fx]!.contains("intensity"))
        let capable = ProgrammerAttributePresentationResolver.capableFixtureIDs(
            attribute: "intensity",
            orderedFixtureIDs: [fx],
            project: project
        )
        XCTAssertEqual(capable, [fx])
    }

    func testUntouchedVirtualIntensityDisplays100Percent() {
        let (project, fx) = rgbOnlyProject()
        let pres = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: [fx],
            project: project,
            programmer: .empty
        )
        XCTAssertTrue(pres.intensity.isSupported)
        XCTAssertEqual(pres.intensity.displayValue ?? -1, 1.0, accuracy: 0.001)
    }

    func testMixedPhysicalAndVirtualIntensityAt100IsCommon() {
        var project = ShowProject.empty(name: "Mix")
        let defPhys = UUID()
        let defVirt = UUID()
        let uni = UUID()
        let a = UUID()
        let b = UUID()
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: defPhys, manufacturer: "T", model: "Head",
                channels: [
                    ChannelDef(offset: 1, name: "Dim", attribute: "intensity"),
                    ChannelDef(offset: 2, name: "R", attribute: "colorR"),
                    ChannelDef(offset: 3, name: "G", attribute: "colorG"),
                    ChannelDef(offset: 4, name: "B", attribute: "colorB"),
                ]
            ),
            FixtureDefinition(
                id: defVirt, manufacturer: "T", model: "PAR",
                channels: [
                    ChannelDef(offset: 1, name: "R", attribute: "colorR"),
                    ChannelDef(offset: 2, name: "G", attribute: "colorG"),
                    ChannelDef(offset: 3, name: "B", attribute: "colorB"),
                ]
            ),
        ]
        project.universes = [Universe(id: uni, number: 1, channelCount: 512)]
        project.fixtures = [
            PatchedFixture(id: a, name: "A", definitionId: defPhys, universeId: uni, address: 1),
            PatchedFixture(id: b, name: "B", definitionId: defVirt, universeId: uni, address: 10),
        ]
        var prog = ProgrammerState.empty
        prog.values[a] = ["intensity": 1.0]
        // b has no intensity — virtual effective 1.0
        let pres = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: [a, b],
            project: project,
            programmer: prog
        )
        XCTAssertEqual(pres.intensity.displayValue ?? -1, 1.0, accuracy: 0.001)
        XCTAssertFalse(pres.intensity.isMixed)
    }
}
