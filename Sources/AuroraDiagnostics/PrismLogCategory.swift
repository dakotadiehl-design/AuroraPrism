import Foundation

/// Stable Unified Logging category names and preference keys. Do not rename casually.
public enum PrismLogCategory: String, CaseIterable, Codable, Sendable, Hashable {
    case appLifecycle = "app.lifecycle"
    case appSettings = "app.settings"
    case appWindowing = "app.windowing"

    case projectDocument = "project.document"
    case projectAutosave = "project.autosave"
    case projectMigration = "project.migration"
    case projectValidation = "project.validation"

    case fixtureLibrary = "fixture.library"
    case fixtureImport = "fixture.import"
    case fixtureLightkey = "fixture.lightkey"

    case engineShow = "engine.show"
    case engineProgrammer = "engine.programmer"
    case engineCues = "engine.cues"
    case engineEffects = "engine.effects"
    case enginePerformance = "engine.performance"

    case ameIngress = "ame.ingress"
    case ameMatching = "ame.matching"
    case ameTransform = "ame.transform"
    case ameSequence = "ame.sequence"
    case ameQuantization = "ame.quantization"
    case ameEmission = "ame.emission"
    case ameHeldState = "ame.heldState"

    case musicClock = "music.clock"
    case musicTransport = "music.transport"
    case musicScheduler = "music.scheduler"
    case musicSong = "music.song"

    case outputRouting = "output.routing"
    case outputLocalDMX = "output.localDMX"
    case outputArtnet = "output.artnet"
    case outputSacn = "output.sacn"

    case controlMIDI = "control.midi"
    case controlOSC = "control.osc"
    case controlRTPMIDI = "control.rtpMIDI"
    case controlKeyboard = "control.keyboard"

    case remoteHost = "remote.host"
    case remoteWeb = "remote.web"
    case remoteSession = "remote.session"
    case remoteCodec = "remote.codec"

    case uiStage = "ui.stage"
    case uiPatch = "ui.patch"
    case uiWorkspace = "ui.workspace"
    case uiPresentation = "ui.presentation"

    public var defaultLevel: PrismLogLevel {
        switch self {
        case .uiStage, .uiPatch, .uiWorkspace, .uiPresentation, .enginePerformance:
            return .error
        default:
            return .notice
        }
    }

    public var group: PrismLogCategoryGroup {
        switch self {
        case .appLifecycle, .appSettings, .appWindowing: return .app
        case .projectDocument, .projectAutosave, .projectMigration, .projectValidation: return .project
        case .fixtureLibrary, .fixtureImport, .fixtureLightkey: return .fixture
        case .engineShow, .engineProgrammer, .engineCues, .engineEffects, .enginePerformance: return .engine
        case .ameIngress, .ameMatching, .ameTransform, .ameSequence, .ameQuantization, .ameEmission, .ameHeldState: return .ame
        case .musicClock, .musicTransport, .musicScheduler, .musicSong: return .music
        case .outputRouting, .outputLocalDMX, .outputArtnet, .outputSacn: return .output
        case .controlMIDI, .controlOSC, .controlRTPMIDI, .controlKeyboard: return .control
        case .remoteHost, .remoteWeb, .remoteSession, .remoteCodec: return .remote
        case .uiStage, .uiPatch, .uiWorkspace, .uiPresentation: return .ui
        }
    }

    public var displayName: String {
        switch self {
        case .appLifecycle: return "Lifecycle"
        case .appSettings: return "Settings"
        case .appWindowing: return "Windowing"
        case .projectDocument: return "Document"
        case .projectAutosave: return "Autosave"
        case .projectMigration: return "Migration"
        case .projectValidation: return "Validation"
        case .fixtureLibrary: return "Library"
        case .fixtureImport: return "Import"
        case .fixtureLightkey: return "LightKey"
        case .engineShow: return "Show engine"
        case .engineProgrammer: return "Programmer"
        case .engineCues: return "Cues"
        case .engineEffects: return "Effects"
        case .enginePerformance: return "Performance"
        case .ameIngress: return "Ingress"
        case .ameMatching: return "Matching"
        case .ameTransform: return "Transform"
        case .ameSequence: return "Sequence"
        case .ameQuantization: return "Quantization"
        case .ameEmission: return "Emission"
        case .ameHeldState: return "Held state"
        case .musicClock: return "Clock"
        case .musicTransport: return "Transport"
        case .musicScheduler: return "Scheduler"
        case .musicSong: return "Song"
        case .outputRouting: return "Routing"
        case .outputLocalDMX: return "Local DMX"
        case .outputArtnet: return "Art-Net"
        case .outputSacn: return "sACN"
        case .controlMIDI: return "MIDI"
        case .controlOSC: return "OSC"
        case .controlRTPMIDI: return "RTP-MIDI"
        case .controlKeyboard: return "Keyboard"
        case .remoteHost: return "Host"
        case .remoteWeb: return "Web"
        case .remoteSession: return "Session"
        case .remoteCodec: return "Codec"
        case .uiStage: return "Stage"
        case .uiPatch: return "Patch"
        case .uiWorkspace: return "Workspace"
        case .uiPresentation: return "Presentation"
        }
    }
}

public enum PrismLogCategoryGroup: String, CaseIterable, Sendable, Codable {
    case app
    case project
    case fixture
    case engine
    case ame
    case music
    case output
    case control
    case remote
    case ui

    public var displayName: String {
        switch self {
        case .app: return "App"
        case .project: return "Project"
        case .fixture: return "Fixture"
        case .engine: return "Show Engine"
        case .ame: return "AME"
        case .music: return "Music Engine"
        case .output: return "Output"
        case .control: return "Control"
        case .remote: return "Remote"
        case .ui: return "UI / Stage / Workspace"
        }
    }

    public var categories: [PrismLogCategory] {
        PrismLogCategory.allCases.filter { $0.group == self }
    }
}
