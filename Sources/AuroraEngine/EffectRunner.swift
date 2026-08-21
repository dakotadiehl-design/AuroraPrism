import AuroraModel
import Foundation

/// Owns live effect instances and applies them to an `ActiveLook` (PR22 / P1-4).
///
/// Thread-safe for engine tick + main-thread control. Apply order is explicit
/// `EffectInstance.order` (not UUID).
public final class EffectRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var effects: [UUID: EffectInstance] = [:]
    /// Compiled in control/edit paths, never rebuilt by the engine frame loop.
    private var compiledEffects: [UUID: CompiledPrismEffect] = [:]
    /// Atomically replaced, pre-sorted, enabled-only evaluator input.
    private var compiledStack: [CompiledPrismEffect] = []
    private var lastResult: EffectEvaluationResult?
    private var nextOrder: Int = 0
    private var compilationContext = EffectDistributionContext()

    public init() {}

    public func upsert(_ effect: EffectInstance) {
        lock.lock()
        var effect = effect
        if effects[effect.id] == nil {
            // New effect: append to end of stack when order left at default 0 and stack non-empty.
            if effect.order == 0, let maxOrder = effects.values.map(\.order).max() {
                effect.order = maxOrder + 1
            }
            nextOrder = max(nextOrder, effect.order + 1)
        }
        effects[effect.id] = effect
        recompileAllLocked()
        lock.unlock()
    }

    public func remove(id: UUID) {
        lock.lock()
        effects[id] = nil
        recompileAllLocked()
        lock.unlock()
    }

    public func clear() {
        lock.lock()
        effects.removeAll()
        compiledEffects.removeAll()
        compiledStack.removeAll()
        lastResult = nil
        nextOrder = 0
        lock.unlock()
    }

    public func setEnabled(id: UUID, enabled: Bool) {
        lock.lock()
        if var effect = effects[id] {
            effect.enabled = enabled
            effects[id] = effect
            recompileAllLocked()
        }
        lock.unlock()
    }

    /// Replace runtime set from durable project definitions.
    /// First-wins on duplicate IDs (never traps — Post-C6 audit).
    public func load(definitions: [EffectDefinition]) {
        lock.lock()
        var map: [UUID: EffectInstance] = [:]
        map.reserveCapacity(definitions.count)
        for def in definitions {
            if map[def.id] == nil {
                map[def.id] = EffectInstance(definition: def)
            }
        }
        effects = map
        recompileAllLocked()
        nextOrder = (effects.values.map(\.order).max() ?? -1) + 1
        lock.unlock()
    }

    /// Updates stage/patch ordering inputs and recompiles the immutable stack.
    /// Spatial orders remain dynamic across Stage edits unless explicitly frozen.
    public func setCompilationContext(_ context: EffectDistributionContext) {
        lock.lock()
        compilationContext = context
        recompileAllLocked()
        lock.unlock()
    }

    /// Moves one effect in the explicit stack and normalizes durable order values.
    public func move(id: UUID, to destination: Int) {
        lock.lock()
        var ordered = effects.values.sorted { $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order }
        guard let source = ordered.firstIndex(where: { $0.id == id }) else { lock.unlock(); return }
        let item = ordered.remove(at: source)
        ordered.insert(item, at: min(max(0, destination), ordered.count))
        for index in ordered.indices { ordered[index].order = index; effects[ordered[index].id] = ordered[index] }
        nextOrder = ordered.count
        recompileAllLocked()
        lock.unlock()
    }

    /// Creates a reusable linked instance. Creative edits to `templateID`
    /// propagate on the next compilation while target and stack state remain local.
    @discardableResult
    public func createLinkedInstance(templateID: UUID, fixtureIDs: [UUID], name: String? = nil) -> UUID? {
        lock.lock()
        guard let template = effects[templateID] else { lock.unlock(); return nil }
        var instance = template
        instance.id = UUID()
        instance.name = name ?? "\(template.name) Linked"
        instance.fixtureIDs = fixtureIDs
        instance.order = nextOrder
        instance.templateEffectID = templateID
        instance.templateLinkMode = .linked
        nextOrder += 1
        effects[instance.id] = instance
        recompileAllLocked()
        lock.unlock()
        return instance.id
    }

    /// Copies the currently resolved template values into an independent instance.
    public func detachTemplate(id: UUID) {
        lock.lock()
        guard let instance = effects[id] else { lock.unlock(); return }
        var context = compilationContext
        context.templateEffects = effects
        var detached = PrismEffectCompiler.compile(instance, context: context).source
        detached.templateEffectID = nil
        detached.templateLinkMode = .detached
        effects[id] = detached
        recompileAllLocked()
        lock.unlock()
    }

    /// Export durable definitions in apply order.
    public func exportDefinitions() -> [EffectDefinition] {
        snapshot().map { $0.asDefinition() }
    }

    /// Ordered snapshot: lower `order` first, then stable id.
    public func snapshot() -> [EffectInstance] {
        lock.lock()
        defer { lock.unlock() }
        return effects.values.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public var runningCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return effects.values.filter(\.enabled).count
    }

    /// Applies all enabled effects to `look` at engine time `time` (seconds).
    public func apply(on look: ActiveLook, time: TimeInterval) -> ActiveLook {
        let compiled = compiledSnapshot()
        let result = PrismEffectEvaluator.evaluateOrdered(baseLook: look, time: time, effects: compiled)
        lock.lock()
        lastResult = result
        lock.unlock()
        return result.semanticLook
    }

    /// Applies an FX-2 timing frame. Callers obtain samples from
    /// `EffectTimingCoordinator`; legacy effects still use `legacyTime`.
    public func apply(on look: ActiveLook, context: EffectEvaluationContext) -> ActiveLook {
        let compiled = compiledSnapshot()
        return apply(on: look, context: context, compiledEffects: compiled)
    }

    /// Evaluates the exact immutable stack used to produce this frame's timing
    /// samples, preventing edit races between timing and semantic evaluation.
    public func apply(
        on look: ActiveLook,
        context: EffectEvaluationContext,
        compiledEffects: [CompiledPrismEffect]
    ) -> ActiveLook {
        let result = PrismEffectEvaluator.evaluateOrdered(baseLook: look, context: context, effects: compiledEffects)
        lock.lock()
        lastResult = result
        lock.unlock()
        return result.semanticLook
    }

    /// Immutable ordered evaluator input. Compilation occurs only when definitions change.
    public func compiledSnapshot() -> [CompiledPrismEffect] {
        lock.lock()
        defer { lock.unlock() }
        return compiledStack
    }

    /// Latest authoritative live evaluation, including evaluator-owned visual metadata.
    public func latestEvaluationResult() -> EffectEvaluationResult? {
        lock.lock()
        defer { lock.unlock() }
        return lastResult
    }

    private func rebuildCompiledStackLocked() {
        compiledStack = compiledEffects.values.filter(\.source.enabled).sorted {
            if $0.source.order != $1.source.order { return $0.source.order < $1.source.order }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func recompileAllLocked() {
        var context = compilationContext
        context.templateEffects = effects
        compiledEffects = effects.mapValues { PrismEffectCompiler.compile($0, context: context) }
        rebuildCompiledStackLocked()
    }

    /// Pure apply for tests and deterministic evaluation.
    public static func apply(
        look: ActiveLook,
        time: TimeInterval,
        effects: [EffectInstance]
    ) -> ActiveLook {
        let compiled = effects.map { PrismEffectCompiler.compile($0) }
        return PrismEffectEvaluator.evaluate(baseLook: look, time: time, effects: compiled).semanticLook
    }
}
