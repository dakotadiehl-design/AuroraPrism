import AuroraModel
import Foundation

/// Starting points used by the operator-facing fixture creator. These are deliberately
/// source-neutral: every result is an ordinary `FixtureDefinition` that can be edited,
/// imported, embedded, and exported like any other personality.
public enum FixtureCreationTemplate: String, CaseIterable, Sendable, Identifiable {
    case dimmer
    case rgb
    case rgbw
    case movingHead
    case fogger
    case hazer
    case snowMachine
    case bubbleMachine
    case fan
    case laser
    case strobe
    case flameEffect
    case generic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dimmer: return "Dimmer"
        case .rgb: return "RGB Light"
        case .rgbw: return "RGBW Light"
        case .movingHead: return "Moving Head"
        case .fogger: return "Fog Machine"
        case .hazer: return "Hazer"
        case .snowMachine: return "Snow Machine"
        case .bubbleMachine: return "Bubble Machine"
        case .fan: return "Fan"
        case .laser: return "Laser"
        case .strobe: return "Strobe"
        case .flameEffect: return "Flame / Pyro Controller"
        case .generic: return "Generic DMX Device"
        }
    }

    public var isSafetySensitive: Bool { self == .flameEffect }
}

public enum FixtureDefinitionFactory {
    public static func make(
        template: FixtureCreationTemplate,
        manufacturer: String = "User",
        model: String? = nil,
        modeName: String = "Default"
    ) -> FixtureDefinition {
        let channels = channels(for: template)
        let physical = physicalDefinition(template: template, manufacturer: manufacturer, model: model ?? template.title)
        let emitsLight = !physical.emitters.isEmpty
        let controlElements = emitsLight ? [FixtureControlElement(id: "fixture-output", name: "Fixture Output")] : []
        let mappings = emitsLight
            ? [FixtureEmitterMapping(id: "fixture-output-map", controlElementIDs: ["fixture-output"], physicalEmitterIDs: Set(physical.emitters.map(\.id)))]
            : []

        return FixtureDefinition(
            manufacturer: manufacturer,
            model: model ?? template.title,
            modeName: modeName,
            channels: channels,
            colorModel: colorModel(for: template),
            hasPanTilt: template == .movingHead,
            category: category(for: template),
            physicalFixtureID: physical.id,
            portablePhysicalDefinition: physical,
            controlElements: controlElements,
            emitterMappings: mappings
        )
    }

    public static func isSafetySensitive(_ definition: FixtureDefinition) -> Bool {
        definition.channels.contains { channel in channel.dmxFunctions.contains(where: \.isProtected) }
    }

    private static func channel(_ offset: UInt16, _ name: String, _ attribute: String, generic: Bool = false) -> ChannelDef {
        ChannelDef(offset: offset, name: name, attribute: attribute, semanticKind: generic ? .generic : .semantic)
    }

    private static func effectChannel(
        _ offset: UInt16,
        _ name: String,
        _ attribute: String,
        activeFrom: UInt8 = 1
    ) -> ChannelDef {
        ChannelDef(
            offset: offset,
            name: name,
            attribute: attribute,
            semanticKind: .generic,
            dmxFunctions: [
                DMXFunctionRange(name: "Off", dmxMin: 0, dmxMax: activeFrom - 1),
                DMXFunctionRange(
                    name: name,
                    dmxMin: activeFrom,
                    dmxMax: 255,
                    attribute: attribute,
                    semantic: .attribute
                ),
            ]
        )
    }

    private static func channels(for template: FixtureCreationTemplate) -> [ChannelDef] {
        switch template {
        case .dimmer:
            return [channel(1, "Intensity", "intensity")]
        case .rgb:
            return [channel(1, "Red", "colorR"), channel(2, "Green", "colorG"), channel(3, "Blue", "colorB")]
        case .rgbw:
            return [channel(1, "Red", "colorR"), channel(2, "Green", "colorG"), channel(3, "Blue", "colorB"), channel(4, "White", "colorW")]
        case .movingHead:
            return [channel(1, "Pan", "pan"), channel(2, "Tilt", "tilt"), channel(3, "Intensity", "intensity"), channel(4, "Red", "colorR"), channel(5, "Green", "colorG"), channel(6, "Blue", "colorB")]
        case .fogger:
            // Common Chauvet Hurricane behavior: 0…5 is off; 6…255 controls output.
            return [effectChannel(1, "Fog Output", "fogOutput", activeFrom: 6)]
        case .hazer:
            return [effectChannel(1, "Haze Output", "hazeOutput"), effectChannel(2, "Fan Speed", "fanSpeed")]
        case .snowMachine:
            return [effectChannel(1, "Snow Output", "snowOutput"), effectChannel(2, "Blower Speed", "fanSpeed")]
        case .bubbleMachine:
            return [effectChannel(1, "Bubble Output", "bubbleOutput"), effectChannel(2, "Fan Speed", "fanSpeed")]
        case .fan:
            return [effectChannel(1, "Fan Speed", "fanSpeed")]
        case .laser:
            return [channel(1, "Intensity", "intensity"), channel(2, "Pattern", "laserPattern", generic: true), channel(3, "Speed", "effectSpeed", generic: true)]
        case .strobe:
            return [channel(1, "Intensity", "intensity"), channel(2, "Strobe Rate", "strobeRate")]
        case .flameEffect:
            return [ChannelDef(
                offset: 1,
                name: "Fire Trigger",
                attribute: "fireTrigger",
                defaultValue: 0,
                highlightValue: 0,
                semanticKind: .generic,
                dmxFunctions: [DMXFunctionRange(
                    name: "Fire",
                    dmxMin: 200,
                    dmxMax: 255,
                    semantic: .protectedCommand,
                    commandCategory: .custom,
                    holdDurationMilliseconds: 1000,
                    requiresConfirmation: true
                )]
            )]
        case .generic:
            return [channel(1, "Channel 1", "generic1", generic: true)]
        }
    }

    private static func colorModel(for template: FixtureCreationTemplate) -> ColorModel? {
        switch template {
        case .rgb, .movingHead: return .rgb
        case .rgbw: return .rgbw
        case .dimmer, .strobe: return .singleColor
        default: return nil
        }
    }

    private static func category(for template: FixtureCreationTemplate) -> String {
        switch template {
        case .fogger: return "fogger"
        case .hazer: return "hazer"
        case .snowMachine: return "snow-machine"
        case .bubbleMachine: return "bubble-machine"
        case .fan: return "fan"
        case .flameEffect: return "safety-effect"
        case .laser: return "laser"
        case .strobe: return "strobe"
        case .movingHead: return "moving-head"
        case .rgb, .rgbw: return "color-light"
        case .dimmer: return "dimmer"
        case .generic: return "generic"
        }
    }

    private static func physicalDefinition(template: FixtureCreationTemplate, manufacturer: String, model: String) -> FixturePhysicalDefinition {
        let form: FixturePhysicalForm
        switch template {
        case .fogger, .hazer, .snowMachine, .bubbleMachine, .fan: form = .atmospheric
        case .movingHead: form = .movingHead
        case .laser: form = .laser
        case .strobe: form = .strobe
        case .rgb, .rgbw: form = .par
        case .dimmer, .generic, .flameEffect: form = .effect
        }
        let emitsLight = [.dimmer, .rgb, .rgbw, .movingHead, .laser, .strobe].contains(template)
        let emitter = FixturePhysicalEmitter(id: "physical-emitter-0", name: "Emitter 1", x: 0.5, y: 0.5, width: 0.58, height: 0.58)
        return FixturePhysicalDefinition(
            manufacturer: manufacturer,
            model: model,
            form: form,
            emitters: emitsLight ? [emitter] : [],
            componentGroups: emitsLight ? [.init(id: "primary", role: .primaryOptic, topology: .single, emitterIDs: [emitter.id])] : [],
            opticalBehaviors: emitsLight ? [.wash] : [],
            movement: template == .movingHead ? .panTilt : .static,
            source: .explicit
        )
    }
}
