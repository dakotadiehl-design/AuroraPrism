import Foundation

/// Diff snapshot of project-level Musical Engine configuration applied by the host.
///
/// Separates **configured external source intent** from active timing policy so
/// `internalOnly → external*` re-entry can re-sync the selected source.
public struct MusicalAppliedProjectConfig: Equatable, Sendable {
    public var tempo: Double
    public var meter: MusicalMeter
    public var freewheelSeconds: Double
    public var timingPolicy: TimingSourcePolicy
    /// Configured external source preference (`uid:` / `ep:`), or nil.
    public var selectedSourceID: String?

    public init(
        tempo: Double,
        meter: MusicalMeter,
        freewheelSeconds: Double,
        timingPolicy: TimingSourcePolicy,
        selectedSourceID: String?
    ) {
        self.tempo = tempo
        self.meter = meter
        self.freewheelSeconds = freewheelSeconds
        self.timingPolicy = timingPolicy
        self.selectedSourceID = selectedSourceID
    }
}

/// Production reconciliation for Musical Engine project settings (Pass 3 P0-1 / P1-2).
///
/// Host code and tests **must** share this component — do not reimplement the rules in tests only.
public enum MusicalTimingConfigReconciler {
    public struct Decision: Equatable, Sendable {
        public var applyProjectDefaults: Bool
        public var applyFreewheelSeconds: Double?
        public var applyTimingPolicy: TimingSourcePolicy?
        /// Sync adapter preferred source + (when desired policy is external-capable) engine selection.
        public var syncExternalSource: Bool
        public var externalSourceID: String?
        public var bootstrapTransportForPolicy: TimingSourcePolicy?

        public init(
            applyProjectDefaults: Bool = false,
            applyFreewheelSeconds: Double? = nil,
            applyTimingPolicy: TimingSourcePolicy? = nil,
            syncExternalSource: Bool = false,
            externalSourceID: String? = nil,
            bootstrapTransportForPolicy: TimingSourcePolicy? = nil
        ) {
            self.applyProjectDefaults = applyProjectDefaults
            self.applyFreewheelSeconds = applyFreewheelSeconds
            self.applyTimingPolicy = applyTimingPolicy
            self.syncExternalSource = syncExternalSource
            self.externalSourceID = externalSourceID
            self.bootstrapTransportForPolicy = bootstrapTransportForPolicy
        }
    }

    /// Compute what the host must apply when moving from `previous` to `desired`.
    public static func decide(
        previous: MusicalAppliedProjectConfig?,
        desired: MusicalAppliedProjectConfig
    ) -> Decision {
        var decision = Decision()

        if previous == nil
            || previous?.tempo != desired.tempo
            || previous?.meter != desired.meter {
            decision.applyProjectDefaults = true
        }

        if previous?.freewheelSeconds != desired.freewheelSeconds {
            decision.applyFreewheelSeconds = desired.freewheelSeconds
        }

        let policyChanged = previous?.timingPolicy != desired.timingPolicy
        let sourceChanged = previous?.selectedSourceID != desired.selectedSourceID

        if policyChanged {
            decision.applyTimingPolicy = desired.timingPolicy
        }

        // Re-apply configured external source when:
        // - the binding/resolution changed, or
        // - policy re-entered an external-capable mode (engine selection was clobbered by internalOnly).
        let needsExternalSourceSync =
            sourceChanged || (policyChanged && desired.timingPolicy != .internalOnly)
        if needsExternalSourceSync {
            decision.syncExternalSource = true
            decision.externalSourceID = desired.selectedSourceID
        }

        if previous == nil || policyChanged {
            decision.bootstrapTransportForPolicy = desired.timingPolicy
        }

        return decision
    }

    /// Apply a transition using production rules (engine + optional clock-adapter preferred source).
    public static func applyTransition(
        previous: MusicalAppliedProjectConfig?,
        desired: MusicalAppliedProjectConfig,
        to engine: MusicalEngine,
        setPreferredSource: ((String?) -> Void)? = nil
    ) {
        let decision = decide(previous: previous, desired: desired)

        if decision.applyProjectDefaults {
            engine.setProjectDefaults(tempoBPM: desired.tempo, meter: desired.meter)
        }
        if let freewheel = decision.applyFreewheelSeconds {
            var est = engine.clockEstimatorConfig
            est.freewheelSeconds = freewheel
            engine.setClockEstimatorConfig(est)
        }
        if let policy = decision.applyTimingPolicy {
            engine.setTimingPolicy(policy)
        }
        if decision.syncExternalSource {
            setPreferredSource?(decision.externalSourceID)
            // Only push engine external selection when desired policy is external-capable.
            if desired.timingPolicy != .internalOnly {
                engine.selectExternalTimingSource(decision.externalSourceID)
            }
        }
        if let policy = decision.bootstrapTransportForPolicy {
            switch policy {
            case .internalOnly, .externalPreferredFallback:
                if engine.state.timing.transport != .running {
                    engine.startTransport()
                }
            case .externalMIDI:
                break
            }
        }
    }
}
