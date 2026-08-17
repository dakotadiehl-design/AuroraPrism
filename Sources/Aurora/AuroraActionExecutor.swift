import AuroraEngine
import AuroraModel
import AuroraMusical
import Foundation

/// Context for generalized AuroraAction execution.
public struct AuroraActionExecutionContext: Sendable {
    public var controlValue: Double
    public var orderedFixtureIDs: [UUID]
    public var selectedFixtureIDs: Set<UUID>
    public var latencyID: UUID?

    public init(
        controlValue: Double = 0,
        orderedFixtureIDs: [UUID] = [],
        selectedFixtureIDs: Set<UUID> = [],
        latencyID: UUID? = nil
    ) {
        self.controlValue = controlValue
        self.orderedFixtureIDs = orderedFixtureIDs
        self.selectedFixtureIDs = selectedFixtureIDs
        self.latencyID = latencyID
    }
}

public enum AuroraActionExecutionOutcome: Equatable, Sendable {
    case executed
    case unsupported
    case partial
}

public enum AuroraActionSupportLevel: Equatable, Sendable {
    case supported
    case supportedWithLimitations(String)
    case unsupported(String)
}

/// Explicit host navigation capabilities — never silent no-ops.
public struct AuroraActionHostCallbacks: @unchecked Sendable {
    public var selectSong: ((UUID) -> AuroraActionExecutionOutcome)?
    public var enterSection: ((UUID) -> AuroraActionExecutionOutcome)?
    public var nextSection: (() -> AuroraActionExecutionOutcome)?
    public var previousSection: (() -> AuroraActionExecutionOutcome)?

    public init(
        selectSong: ((UUID) -> AuroraActionExecutionOutcome)? = nil,
        enterSection: ((UUID) -> AuroraActionExecutionOutcome)? = nil,
        nextSection: (() -> AuroraActionExecutionOutcome)? = nil,
        previousSection: (() -> AuroraActionExecutionOutcome)? = nil
    ) {
        self.selectSong = selectSong
        self.enterSection = enterSection
        self.nextSection = nextSection
        self.previousSection = previousSection
    }
}

/// Integration-layer executor. Truthful support depends on installed host callbacks.
public final class AuroraActionExecutor: @unchecked Sendable {
    private weak var lighting: LightingEngine?
    private weak var musical: MusicalEngine?
    private weak var ame: AMERuntime?
    private var project: ShowProject
    public var host: AuroraActionHostCallbacks

    public init(
        lighting: LightingEngine?,
        musical: MusicalEngine?,
        ame: AMERuntime?,
        project: ShowProject,
        host: AuroraActionHostCallbacks = AuroraActionHostCallbacks()
    ) {
        self.lighting = lighting
        self.musical = musical
        self.ame = ame
        self.project = project
        self.host = host
    }

    public func updateProject(_ project: ShowProject) {
        self.project = project
    }

    /// Instance capability: only `supported` when the host can actually perform the action.
    public func supportLevel(for action: AuroraAction) -> AuroraActionSupportLevel {
        switch action {
        case .compound(let inner):
            let levels = inner.map { supportLevel(for: $0) }
            if levels.allSatisfy({ if case .supported = $0 { return true }; return false }) {
                return .supported
            }
            if levels.contains(where: { if case .supported = $0 { return true }; return false }) {
                return .supportedWithLimitations("partial compound")
            }
            return .unsupported("compound has no supported children")
        case .go, .stop, .back, .fireCue, .fireCueIndex,
             .blackout, .blackoutOff, .toggleBlackout,
             .freeze, .freezeOff, .toggleFreeze,
             .blind, .blindOff, .toggleBlind,
             .masterIntensity, .panic, .clearOverrides, .toggleMIDIPerformance,
             .programmerAttribute:
            return lighting == nil ? .unsupported("no lighting engine") : .supported
        case .tapTempo, .setTransportStart, .setTransportStop, .setTransportContinue, .setTempoBPM:
            return musical == nil ? .unsupported("no musical engine") : .supported
        case .resetSequence, .advanceSequence, .fireSequenceStep:
            return ame == nil ? .unsupported("no AME runtime") : .supported
        case .selectSong:
            return host.selectSong == nil ? .unsupported("selectSong host not wired") : .supported
        case .enterSection:
            return host.enterSection == nil ? .unsupported("enterSection host not wired") : .supported
        case .nextSection:
            return host.nextSection == nil ? .unsupported("nextSection host not wired") : .supported
        case .previousSection:
            return host.previousSection == nil ? .unsupported("previousSection host not wired") : .supported
        case .triggerEffect, .setEffectRate, .setEffectDepth,
             .firePreset, .firePalette, .fireLook, .runBehavior:
            return .unsupported("product path not wired")
        }
    }

    public static func isSupported(_ action: AuroraAction) -> Bool {
        // Static list cannot know host hooks — prefer instance supportLevel.
        switch action {
        case .triggerEffect, .setEffectRate, .setEffectDepth,
             .firePreset, .firePalette, .fireLook, .runBehavior:
            return false
        default:
            return true
        }
    }

    @discardableResult
    public func execute(_ action: AuroraAction, context: AuroraActionExecutionContext) -> AuroraActionExecutionOutcome {
        if case .compound(let inner) = action {
            var any = false
            var unsupported = false
            for a in inner {
                switch execute(a, context: context) {
                case .executed: any = true
                case .partial: any = true
                case .unsupported: unsupported = true
                }
            }
            if any && unsupported { return .partial }
            if any { return .executed }
            return .unsupported
        }

        switch supportLevel(for: action) {
        case .unsupported:
            return .unsupported
        default:
            break
        }

        // Sequence control works without lighting.
        if case .advanceSequence(let id) = action {
            guard let ame else { return .unsupported }
            return ame.advanceSequence(id: id) ? .executed : .unsupported
        }
        if case .fireSequenceStep(let id, let step) = action {
            guard let ame, let actions = ame.fireSequenceStepActions(sequenceID: id, stepIndex: step) else {
                return .unsupported
            }
            if actions.isEmpty { return .executed }
            return execute(.compound(actions), context: context)
        }
        if case .resetSequence(let id) = action {
            guard let ame else { return .unsupported }
            return ame.resetSequence(id: id) ? .executed : .unsupported
        }

        guard let eng = lighting else {
            // Musical-only / host nav actions may still run.
            return executeMusicalOnly(action) ? .executed : .unsupported
        }

        switch action {
        case .go: eng.go()
        case .stop: eng.stopPlayback()
        case .back: eng.back()
        case .fireCue(let id):
            return eng.fire(cueID: id) ? .executed : .unsupported
        case .fireCueIndex(let index):
            guard index >= 0 else { return .unsupported }
            let list: CueList?
            if let listID = eng.playback.snapshot().listID {
                list = project.cueLists.first(where: { $0.id == listID })
            } else {
                list = project.cueLists.first
            }
            guard let list, list.cues.indices.contains(index) else { return .unsupported }
            return eng.fire(cueID: list.cues[index].id) ? .executed : .unsupported
        case .blackout: eng.setBlackout(true)
        case .blackoutOff: eng.setBlackout(false)
        case .toggleBlackout: eng.toggleBlackout()
        case .freeze: eng.setFreeze(true)
        case .freezeOff: eng.setFreeze(false)
        case .toggleFreeze: eng.toggleFreeze()
        case .blind: eng.setBlind(true)
        case .blindOff: eng.setBlind(false)
        case .toggleBlind: eng.toggleBlind()
        case .masterIntensity: eng.setMasterIntensity(context.controlValue)
        case .panic: eng.panic()
        case .clearOverrides: eng.clearOverrides()
        case .toggleMIDIPerformance: eng.toggleMIDIPerformance()
        case .programmerAttribute(let attr):
            let targets = context.orderedFixtureIDs.isEmpty
                ? Array(context.selectedFixtureIDs)
                : context.orderedFixtureIDs
            for id in targets {
                eng.programmer.set(fixtureID: id, attribute: attr, value: context.controlValue)
            }
        case .selectSong(let id):
            return host.selectSong?(id) ?? .unsupported
        case .enterSection(let id):
            return host.enterSection?(id) ?? .unsupported
        case .nextSection:
            return host.nextSection?() ?? .unsupported
        case .previousSection:
            return host.previousSection?() ?? .unsupported
        case .tapTempo:
            _ = musical?.tapTempo()
        case .setTransportStart:
            musical?.startTransport()
        case .setTransportStop:
            musical?.stopTransport()
        case .setTransportContinue:
            musical?.continueTransport()
        case .setTempoBPM(let bpm):
            musical?.setTempoBPM(bpm)
        case .resetSequence, .advanceSequence, .fireSequenceStep:
            // Handled above.
            break
        case .triggerEffect, .setEffectRate, .setEffectDepth,
             .firePreset, .firePalette, .fireLook, .runBehavior:
            return .unsupported
        case .compound:
            break
        }
        return .executed
    }

    private func executeMusicalOnly(_ action: AuroraAction) -> Bool {
        switch action {
        case .tapTempo:
            guard let musical else { return false }
            _ = musical.tapTempo()
            return true
        case .setTransportStart:
            guard let musical else { return false }
            musical.startTransport()
            return true
        case .setTransportStop:
            guard let musical else { return false }
            musical.stopTransport()
            return true
        case .setTransportContinue:
            guard let musical else { return false }
            musical.continueTransport()
            return true
        case .setTempoBPM(let bpm):
            guard let musical else { return false }
            musical.setTempoBPM(bpm)
            return true
        case .resetSequence(let id):
            guard let ame else { return false }
            return ame.resetSequence(id: id)
        case .advanceSequence(let id):
            return ame?.advanceSequence(id: id) == true
        case .fireSequenceStep(let id, let step):
            guard let ame, let actions = ame.fireSequenceStepActions(sequenceID: id, stepIndex: step) else {
                return false
            }
            if actions.isEmpty { return true }
            // Nested execute without lighting path for pure musical/sequence children.
            return execute(.compound(actions), context: AuroraActionExecutionContext()) != .unsupported
        case .selectSong(let id):
            return host.selectSong?(id) == .executed
        case .enterSection(let id):
            return host.enterSection?(id) == .executed
        case .nextSection:
            return host.nextSection?() == .executed
        case .previousSection:
            return host.previousSection?() == .executed
        default:
            return false
        }
    }
}
