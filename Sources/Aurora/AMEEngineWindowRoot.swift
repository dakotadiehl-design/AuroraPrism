import AuroraCore
import AuroraEngine
import AuroraModel
import AuroraMusical
import AuroraUI
import SwiftUI

/// Window root for Window → MIDI Engine… (Phase F / Wave 5 editor).
///
/// Presentation refresh must **not** replace view identity (no `.id(pollTick)`).
/// AME Learn is owned by the router; closing this window always cancels armed Learn.
struct AMEEngineWindowRoot: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedMappingID: UUID?
    @State private var selectedTriggerID: UUID?
    @State private var selectedSequenceID: UUID?
    /// Presentation snapshots — updated by timer without tearing down the editor tree.
    @State private var musicalState: MusicalState = MusicalState()
    @State private var monitorEvents: [AMEDiagnosticEvent] = []
    @State private var isLearning = false
    @State private var lastCommandError: String?

    var body: some View {
        let project = appModel.session.project
        let mode = appModel.showControl.controlRouter.amePerformanceMode
        let issues = AMEConfigurationValidator.validate(project: project)

        AMEEnginePanel(
            project: project,
            performanceMode: mode,
            onPerformanceModeChange: { newMode in
                appModel.showControl.controlRouter.amePerformanceMode = newMode
                appModel.notifyUI()
            },
            musicalState: musicalState,
            monitorEvents: monitorEvents,
            validationIssues: issues,
            selectedMappingID: selectedMappingID,
            selectedTriggerID: selectedTriggerID,
            selectedSequenceID: selectedSequenceID,
            isLearning: isLearning || appModel.showControl.controlRouter.isAMELearning,
            onSelectMapping: {
                selectedMappingID = $0
                selectedTriggerID = nil
                selectedSequenceID = nil
            },
            onSelectTrigger: {
                selectedTriggerID = $0
                selectedMappingID = nil
                selectedSequenceID = nil
            },
            onSelectSequence: {
                selectedSequenceID = $0
                selectedMappingID = nil
                selectedTriggerID = nil
            },
            onAddTrigger: {
                let t = AMETriggerDefinition(name: "Trigger \(project.ame.triggers.count + 1)")
                perform(UpsertAMETriggerCommand(trigger: t))
                selectedTriggerID = t.id
                selectedMappingID = nil
                selectedSequenceID = nil
            },
            onAddMapping: {
                let m = AMEMapping(name: "Mapping \(project.ame.mappings.count + 1)", actions: [.go])
                perform(UpsertAMEMappingCommand(mapping: m))
                selectedMappingID = m.id
                selectedTriggerID = nil
                selectedSequenceID = nil
            },
            onAddSequence: {
                let s = AMETriggeredSequence(
                    name: "Sequence \(project.ame.sequences.count + 1)",
                    steps: [AMESequenceStep(name: "Step 1", actions: [.go])]
                )
                perform(UpsertAMESequenceCommand(sequence: s))
                selectedSequenceID = s.id
                selectedMappingID = nil
                selectedTriggerID = nil
            },
            onDeleteMapping: { id in
                perform(RemoveAMEMappingCommand(mappingID: id))
                if selectedMappingID == id { selectedMappingID = nil }
            },
            onDeleteTrigger: { id in
                perform(RemoveAMETriggerCommand(triggerID: id))
                if selectedTriggerID == id { selectedTriggerID = nil }
            },
            onDeleteSequence: { id in
                perform(RemoveAMESequenceCommand(sequenceID: id))
                if selectedSequenceID == id { selectedSequenceID = nil }
            },
            onDuplicateMapping: { id in
                perform(DuplicateAMEMappingCommand(mappingID: id))
            },
            onDuplicateTrigger: { id in
                perform(DuplicateAMETriggerCommand(triggerID: id))
            },
            onDuplicateSequence: { id in
                perform(DuplicateAMESequenceCommand(sequenceID: id))
            },
            onUpdateMapping: { mapping in
                perform(UpsertAMEMappingCommand(mapping: mapping, name: "Edit AME Mapping"))
            },
            onUpdateTrigger: { trigger in
                perform(UpsertAMETriggerCommand(trigger: trigger, name: "Edit AME Trigger"))
            },
            onUpdateSequence: { sequence in
                perform(UpsertAMESequenceCommand(sequence: sequence, name: "Edit AME Sequence"))
            },
            onUpdateMusicalSettings: { settings in
                perform(SetAMEMusicalSettingsCommand(settings: settings))
            },
            onUpsertSourceBinding: { binding in
                perform(UpsertMIDISourceBindingCommand(binding: binding))
            },
            onDeleteSourceBinding: { id in
                perform(RemoveMIDISourceBindingCommand(bindingID: id))
            },
            onLearn: {
                isLearning = true
                appModel.showControl.controlRouter.beginAMELearn(name: "Learned")
            },
            onCancelLearn: {
                cancelLearnFully()
            },
            onSelectValidationIssue: { issue in
                guard let rid = issue.relatedID else { return }
                if project.ame.mappings.contains(where: { $0.id == rid }) {
                    selectedMappingID = rid
                    selectedTriggerID = nil
                    selectedSequenceID = nil
                } else if project.ame.triggers.contains(where: { $0.id == rid }) {
                    selectedTriggerID = rid
                    selectedMappingID = nil
                    selectedSequenceID = nil
                } else if project.ame.sequences.contains(where: { $0.id == rid }) {
                    selectedSequenceID = rid
                    selectedMappingID = nil
                    selectedTriggerID = nil
                }
            }
        )
        .frame(minWidth: 960, minHeight: 600)
        .overlay(alignment: .bottom) {
            if let lastCommandError {
                Text(lastCommandError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding()
            }
        }
        // Presentation refresh only — never replace root identity.
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            refreshPresentation()
            // Commit pending AME Learn proposal while window is open.
            if appModel.showControl.controlRouter.isAMELearning || isLearning,
               let proposal = appModel.showControl.controlRouter.consumeAMELearnProposal() {
                isLearning = false
                perform(
                    CommitAMELearnCommand(
                        binding: proposal.binding,
                        trigger: proposal.trigger,
                        mapping: proposal.mapping
                    )
                )
                selectedMappingID = proposal.mapping.id
                selectedTriggerID = proposal.trigger.id
            }
            // Keep UI Learn flag aligned with router truth.
            isLearning = appModel.showControl.controlRouter.isAMELearning
        }
        .onAppear {
            refreshPresentation()
            isLearning = appModel.showControl.controlRouter.isAMELearning
        }
        .onDisappear {
            // P0-3: never leave Learn armed after window close.
            cancelLearnFully()
        }
    }

    private func refreshPresentation() {
        appModel.showControl.controlRouter.refreshAMETimingFromMusicalEngine()
        musicalState = appModel.showControl.musicalEngine.state
        monitorEvents = appModel.showControl.controlRouter.recentAMEMonitorEvents(limit: 100)
    }

    private func cancelLearnFully() {
        isLearning = false
        appModel.showControl.controlRouter.cancelAMELearn()
    }

    private func perform(_ command: any Command) {
        do {
            try appModel.session.perform(command)
            lastCommandError = nil
            appModel.notifyUI()
        } catch {
            lastCommandError = error.localizedDescription
            appModel.diagnostics.log("AME editor command failed: \(error)", subsystem: .app)
        }
    }
}
