import AuroraCore
import AuroraMIDI
import AuroraModel
import AuroraUI
import SwiftUI

/// Native Settings shell (UI-02C). Thin real MIDI; other pages may be placeholders.
struct AuroraSettingsRoot: View {
    @EnvironmentObject private var appModel: AppModel

    /// Local value while dragging frame-rate slider; commit only on end (UI-02 C3).
    @State private var draftFrameRateHz: Double = 40
    @State private var frameRateEditing = false

    var body: some View {
        TabView {
            generalPage
                .tabItem { Label("General", systemImage: "gearshape") }
            midiPage
                .tabItem { Label("MIDI", systemImage: "pianokeys") }
            controlPlaceholders
                .tabItem { Label("Control", systemImage: "slider.horizontal.3") }
            outputPage
                .tabItem { Label("Output", systemImage: "antenna.radiowaves.left.and.right") }
            remotePage
                .tabItem { Label("Remote", systemImage: "iphone") }
            advancedPage
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(minWidth: 520, minHeight: 380)
        .preferredColorScheme(.dark)
        .onAppear {
            draftFrameRateHz = appModel.settings.preferredFrameRateHz
        }
    }

    // MARK: General

    private var generalPage: some View {
        Form {
            scopeHeader("APPLICATION")
            Section("Engine") {
                HStack {
                    Text("Preferred frame rate")
                    Spacer()
                    Text("\(Int(frameRateEditing ? draftFrameRateHz : appModel.settings.preferredFrameRateHz)) Hz")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $draftFrameRateHz,
                    in: 20...44,
                    step: 1,
                    onEditingChanged: { editing in
                        frameRateEditing = editing
                        if !editing {
                            appModel.setPreferredFrameRateHz(draftFrameRateHz)
                        }
                    }
                )
                Text("Changing frame rate reconfigures the running engine when you release the slider.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section("Console") {
                Toggle(
                    "Show timestamps",
                    isOn: Binding(
                        get: { appModel.settings.showConsoleTimestamps },
                        set: {
                            appModel.settings.showConsoleTimestamps = $0
                            appModel.settings.save()
                        }
                    )
                )
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: MIDI (thin real)

    private var midiPage: some View {
        Form {
            scopeHeader("APPLICATION")
            Section("MIDI devices / session") {
                Text(appModel.midiStatus)
                    .font(.body.monospaced())
                Text(appModel.input.lastMIDIEvent.isEmpty ? "No recent events" : appModel.input.lastMIDIEvent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            scopeHeader("PROJECT")
            Section("MIDI mappings") {
                if appModel.session.project.midiMappings.isEmpty {
                    Text("No mappings in this show.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appModel.session.project.midiMappings) { mapping in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(mapping.action)
                                Text("\(mapping.messageType)  d1=\(mapping.data1.map(String.init) ?? "—")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Delete", role: .destructive) {
                                deleteMIDIMapping(mapping.id)
                            }
                            .controlSize(.small)
                        }
                    }
                }
                HStack {
                    if appModel.isMIDILearning {
                        Text("Learning… send MIDI")
                            .foregroundStyle(.orange)
                        Button("Cancel") { appModel.cancelMIDILearn() }
                    } else {
                        Button("Learn Go") { appModel.armMIDILearn(.go) }
                        Button("Learn Stop") { appModel.armMIDILearn(.stop) }
                        Button("Learn Back") { appModel.armMIDILearn(.back) }
                        Button("Learn Intensity CC") { appModel.armMIDILearn(.programmerAttribute("intensity")) }
                    }
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func deleteMIDIMapping(_ id: UUID) {
        do {
            try appModel.session.perform(RemoveMIDIMappingCommand(mappingID: id))
            appModel.notifyUI()
        } catch {
            appModel.document.statusMessage = "Delete mapping failed: \(error.localizedDescription)"
            appModel.diagnostics.log("MIDI mapping delete failed: \(error.localizedDescription)", subsystem: .midi)
            appModel.notifyUI()
        }
    }

    // MARK: Placeholders

    private var controlPlaceholders: some View {
        Form {
            scopeHeader("APPLICATION")
            Section("RTP-MIDI") {
                unavailable("RTP-MIDI session UI is not configured in Settings yet.")
            }
            Section("OSC") {
                unavailable("OSC configuration UI is reserved for a later Settings pass.")
            }
            Section("Keyboard") {
                Text("Use standard macOS shortcuts (⌘N, ⌘O, ⌘S, Space for GO when not editing text).")
                    .foregroundStyle(.secondary)
                Text("Full shortcut customization is not implemented.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var outputPage: some View {
        Form {
            scopeHeader("APPLICATION")
            Section("Status") {
                Text(appModel.output.presentationSnapshot().statusLine)
                    .font(.body.monospaced())
            }
            Section("Local DMX (USB Pro framing — not Open DMX)") {
                HStack {
                    Button("Rescan") {
                        appModel.output.rescanLocalDMXDevices()
                    }
                    Spacer()
                    Text(appModel.output.localDMXStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if appModel.output.availableLocalDMXDevices.isEmpty {
                    Text("No serial devices found. Plug in ENTTEC DMX USB Pro and Rescan.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Picker("Device", selection: Binding(
                        get: { appModel.output.selectedLocalDMXDeviceID ?? "" },
                        set: { appModel.output.selectedLocalDMXDeviceID = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("None").tag("")
                        ForEach(appModel.output.availableLocalDMXDevices) { dev in
                            Text(dev.displayName).tag(dev.id)
                        }
                    }
                }
                Toggle("Enable Local DMX", isOn: Binding(
                    get: { appModel.output.localDMXEnabled },
                    set: { on in
                        appModel.output.setLocalDMXEnabled(
                            on,
                            engineRunning: appModel.performance.engineRunning,
                            log: { appModel.diagnostics.log($0) }
                        )
                    }
                ))
                Text("Local DMX currently maps Show Universe 1 to ENTTEC physical output.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("Serial list shows USB-serial candidates; not all are confirmed ENTTEC.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section("Network drivers") {
                Text("Enable Art-Net / sACN from the Output menu. Destination defaults are application-level.")
                    .foregroundStyle(.secondary)
            }

            scopeHeader("PROJECT")
            Section("Universe routing") {
                Text("Choose where each show universe is sent. Demo defaults stay None (safe).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if appModel.session.project.universes.isEmpty {
                    Text("No universes in this show.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(appModel.session.project.universes) { u in
                        HStack {
                            Text("U\(u.number) \(u.name)")
                            Spacer()
                            Picker("Route", selection: Binding(
                                get: {
                                    appModel.session.project.universes
                                        .first(where: { $0.id == u.id })?.protocolHint ?? .none
                                },
                                set: { hint in
                                    setUniverseRoute(universeID: u.id, hint: hint)
                                }
                            )) {
                                Text("None").tag(UniverseProtocolHint.none)
                                Text("Local DMX").tag(UniverseProtocolHint.local)
                                Text("Art-Net").tag(UniverseProtocolHint.artNet)
                                Text("sACN").tag(UniverseProtocolHint.sACN)
                                Text("Mirror").tag(UniverseProtocolHint.mirror)
                            }
                            .labelsHidden()
                            .frame(maxWidth: 140)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func setUniverseRoute(universeID: UUID, hint: UniverseProtocolHint) {
        do {
            try appModel.session.perform(
                UpdateUniverseRoutingCommand(universeID: universeID, protocolHint: hint)
            )
            appModel.notifyUI()
        } catch {
            appModel.diagnostics.log(error.localizedDescription)
        }
    }

    private var remotePage: some View {
        Form {
            scopeHeader("APPLICATION")
            Section("Web / remote") {
                Text(appModel.remote.remoteStatus)
                    .font(.body.monospaced())
                unavailable("Full remote security/clients UI is a later Settings pass.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var advancedPage: some View {
        Form {
            scopeHeader("APPLICATION")
            Section("Plugins") {
                unavailable("Dynamic plugins are not available.")
            }
            Section("Diagnostics") {
                Text("Validation issues: \(appModel.performance.validationIssueCount)")
                Text("Use the Console panel in Build for typed logs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: Scope grammar

    private func scopeHeader(_ label: String) -> some View {
        HStack {
            Spacer()
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
        }
        .listRowBackground(Color.clear)
    }

    private func unavailable(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}
