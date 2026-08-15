import AuroraEngine
import AuroraModel
import AuroraOutput
import XCTest

@MainActor
final class MIDIBehaviorRuntimeTests: XCTestCase {
    func testEnvelopeDrumFlashPeaksAndDecays() {
        let env = MIDIEnvelopeSpec.drumFlash
        XCTAssertGreaterThan(env.level(at: 0.01, released: false, releaseStart: nil), 0.5)
        XCTAssertEqual(env.level(at: 2.0, released: false, releaseStart: nil), 0, accuracy: 0.01)
    }

    func testDrumRoleResolution() {
        let kit = DrumDeviceProfile.generalMIDIKit
        XCTAssertEqual(kit.role(for: 36, deviceID: nil, songSection: nil), .kick)
        XCTAssertEqual(kit.role(for: 38, deviceID: nil, songSection: nil), .snare)
        XCTAssertNil(kit.role(for: 10, deviceID: nil, songSection: nil))
    }

    func testBehaviorAppliesToLook() throws {
        var project = ShowProject.empty(name: "Beh")
        let u = Universe(number: 1)
        let def = FixtureDefinition(
            manufacturer: "G",
            model: "Dim",
            channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
        )
        let fx = UUID()
        project.universes = [u]
        project.fixtureDefinitions = [def]
        project.fixtures = [
            PatchedFixture(id: fx, name: "D1", definitionId: def.id, universeId: u.id, address: 1),
        ]
        project.drumProfiles = [.generalMIDIKit]
        project.midiBehaviors = [
            MIDIBehaviorDefinition(
                name: "Kick Hit",
                drumRole: .kick,
                attribute: "intensity",
                fixtureIDs: [fx],
                peakLevel: 1,
                velocityScale: true,
                // Zero attack so the first frame after trigger is at full peak.
                envelope: MIDIEnvelopeSpec(kind: .ahdr, attack: 0, hold: 0.5, decay: 0.1, sustain: 0, release: 0.1)
            ),
        ]

        let eng = LightingEngine(output: OutputManager())
        eng.load(project: project)
        try eng.start()
        eng.stepForTesting()
        let t = eng.currentResolvedSnapshot().timestamp
        eng.midiBehaviors.noteOn(
            note: 36,
            velocity: 127,
            channel: 0,
            deviceID: "kit",
            songSection: nil,
            time: t,
            selection: [fx]
        )
        eng.stepForTesting()
        // Shortly after attack, intensity should be high on output.
        let dmx = eng.currentSnapshot().universeLevels[1]?[0] ?? 0
        XCTAssertGreaterThan(dmx, 50)
        eng.stop()
    }

    func testCellChaseEffect() {
        let fx = UUID()
        let effect = EffectInstance(
            kind: .cellChase,
            rateHz: 0,
            size: 1,
            phase: 0,
            attribute: "colorR",
            fixtureIDs: [fx],
            cellCount: 4
        )
        // phase 0, rate 0 → active cell 0
        let look = EffectRunner.apply(look: .empty, time: 0, effects: [effect])
        XCTAssertEqual(look.fixtureAttributes[fx]?["colorR@0"] ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(look.fixtureAttributes[fx]?["colorR@1"] ?? 1, 0, accuracy: 0.001)
    }

    func testPositionCircleWritesPanTilt() {
        let fx = UUID()
        let effect = EffectInstance(
            kind: .positionCircle,
            rateHz: 0,
            size: 1,
            phase: 0,
            fixtureIDs: [fx]
        )
        let look = EffectRunner.apply(look: .empty, time: 0, effects: [effect])
        XCTAssertEqual(look.fixtureAttributes[fx]?["pan"] ?? 0, 1.0, accuracy: 0.01) // cos0=1 → 0.5+0.5
        XCTAssertEqual(look.fixtureAttributes[fx]?["tilt"] ?? 0, 0.5, accuracy: 0.01)
    }

    func testChannelAttribution() {
        var project = ShowProject.empty(name: "A")
        let u = Universe(number: 1)
        let def = FixtureDefinition(
            manufacturer: "G",
            model: "RGB",
            channels: [
                ChannelDef(offset: 1, name: "R", attribute: "colorR"),
                ChannelDef(offset: 2, name: "G", attribute: "colorG"),
                ChannelDef(offset: 3, name: "B", attribute: "colorB"),
            ]
        )
        let fx = UUID()
        project.universes = [u]
        project.fixtureDefinitions = [def]
        project.fixtures = [
            PatchedFixture(id: fx, name: "Wash", definitionId: def.id, universeId: u.id, address: 10),
        ]
        let levels = [UInt8](repeating: 0, count: 20)
        let attrs = DMXChannelAttributionBuilder.attributes(project: project, universeNumber: 1, levels: levels)
        XCTAssertEqual(attrs[9].fixtureName, "Wash") // ch 10
        XCTAssertEqual(attrs[9].parameter, "colorR")
        XCTAssertTrue(attrs[0].isUnused)
    }
}
