import AuroraCore
import AuroraDiagnostics
import AuroraMIDI
import AuroraModel
import AuroraUI
import AppKit
import SwiftUI

/// Native Settings shell (UI-02C).
///
/// **Important:** This root holds `AppModel` by reference only — it is **not** an
/// `@EnvironmentObject` / `@ObservedObject` of the high-frequency composition root.
/// Engine status (~4 Hz) and diagnostics timers otherwise rebuild the entire
/// `TabView`, which restarts SF Symbol tab icons (“twitching”) even with no mouse input.
struct AuroraSettingsRoot: View {
    let appModel: AppModel

    var body: some View {
        TabView {
            SettingsGeneralTab()
                .environmentObject(appModel)
                .tabItem { settingsTabLabel("General", systemImage: "gearshape") }
            SettingsFixtureLibraryTab()
                .environmentObject(appModel)
                .tabItem { settingsTabLabel("Fixture Library", systemImage: "books.vertical") }
            SettingsMIDITab()
                .environmentObject(appModel)
                .tabItem { settingsTabLabel("MIDI", systemImage: "pianokeys") }
            SettingsControlTab()
                .environmentObject(appModel)
                .tabItem { settingsTabLabel("Control", systemImage: "slider.horizontal.3") }
            SettingsOutputTab()
                .environmentObject(appModel)
                .tabItem { settingsTabLabel("Output", systemImage: "antenna.radiowaves.left.and.right") }
            SettingsRemoteTab()
                .environmentObject(appModel)
                .tabItem { settingsTabLabel("Remote", systemImage: "iphone") }
            SettingsLoggingTab(
                initial: appModel.settings.loggingConfiguration,
                apply: { appModel.settings.applyLoggingConfiguration($0) }
            )
            .tabItem { settingsTabLabel("Logging", systemImage: "text.alignleft") }
            SettingsAdvancedTab()
                .environmentObject(appModel)
                .tabItem { settingsTabLabel("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(minWidth: 520, minHeight: 380)
        .preferredColorScheme(.dark)
    }

    /// Monochrome icons — avoids variable-color SF Symbol re-animation on incidental redraws.
    private func settingsTabLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
        }
    }
}

private struct SettingsFixtureLibraryTab: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var errorReport: PrismErrorReport?

    var body: some View {
        Form {
            settingsScopeHeader("APPLICATION")
            Section("User Library Directory") {
                Text(appModel.document.userFixtureLibraryDirectory.path)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                HStack {
                    Button("Choose…") { chooseDirectory() }
                    Button("Use Default") { setDirectory(nil) }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([appModel.document.userFixtureLibraryDirectory])
                    }
                }
                Text("Imported fixture profiles are stored here and are available to every show. Profiles used by a show are also embedded in that project for portability.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section("Status") {
                LabeledContent("User modes", value: "\(appModel.document.userFixtureDefinitions.count)")
                LabeledContent("Built-in modes", value: "\(appModel.document.fixtureLibrary?.definitions.count ?? 0)")
                Button("Reload Library") {
                    do {
                        try appModel.document.reloadUserFixtureLibrary()
                        appModel.notifyUI()
                    } catch {
                        errorReport = PrismErrorReporting.report(
                            error: error,
                            context: PrismErrorContext(
                                operation: "reload fixture library",
                                category: .fixtureLibrary,
                                fallbackTitle: "Prism Couldn't Update the Fixture Library",
                                fallbackMessage: "The Fixture Library could not be updated.",
                                eventCode: "fixture.library.load_failed"
                            )
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .prismErrorAlert(item: $errorReport)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = appModel.document.userFixtureLibraryDirectory
        panel.prompt = "Use Directory"
        guard panel.runModal() == .OK else { return }
        setDirectory(panel.url)
    }

    private func setDirectory(_ url: URL?) {
        do {
            try appModel.document.setUserFixtureLibraryDirectory(url)
            appModel.notifyUI()
        } catch {
            errorReport = PrismErrorReporting.report(
                error: error,
                context: PrismErrorContext(
                    operation: "set fixture library directory",
                    category: .fixtureLibrary,
                    fallbackTitle: "Prism Couldn't Update the Fixture Library",
                    fallbackMessage: "The Fixture Library could not be updated.",
                    eventCode: "fixture.library.failed"
                )
            )
        }
    }
}

// MARK: - Shared chrome

private func settingsScopeHeader(_ label: String) -> some View {
    HStack {
        Spacer()
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
    }
    .listRowBackground(Color.clear)
}

private func settingsUnavailable(_ message: String) -> some View {
    Text(message)
        .font(.caption)
        .foregroundStyle(.tertiary)
}

// MARK: - General

private struct SettingsGeneralTab: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var draftFrameRateHz: Double = 40
    @State private var frameRateEditing = false

    var body: some View {
        Form {
            settingsScopeHeader("APPLICATION")
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
            Section("Appearance") {
                Text("Density customization is not applied by the shell yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            draftFrameRateHz = appModel.settings.preferredFrameRateHz
        }
    }
}

// MARK: - MIDI

private struct SettingsMIDITab: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            settingsScopeHeader("APPLICATION")
            Section("MIDI devices / session") {
                Text(appModel.midiHealth.statusLine)
                    .font(.body.monospaced())
                Text("State: \(appModel.midiHealth.state.rawValue) · sources: \(appModel.midiHealth.connectedSourceCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(appModel.input.lastMIDIEvent.isEmpty ? "No recent events" : appModel.input.lastMIDIEvent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsScopeHeader("PROJECT")
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
            appModel.document.statusMessage = prismReportCommandFailure(
                error,
                operation: "delete MIDI mapping",
                category: .controlMIDI
            )
            appModel.notifyUI()
        }
    }
}

// MARK: - Control

private struct SettingsControlTab: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            settingsScopeHeader("APPLICATION")
            Section("RTP-MIDI") {
                Text(appModel.input.rtpMIDI.statusLine())
                    .font(.body.monospaced())
                Toggle("Enable RTP-MIDI", isOn: Binding(
                    get: { appModel.rtpMIDI.configSnapshot.enabled },
                    set: { appModel.setRTPMIDIEnabled($0) }
                ))
                Text("Session: \(appModel.rtpMIDI.localName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("OSC") {
                Text(appModel.oscStatus)
                    .font(.body.monospaced())
                Toggle("Enable OSC (UDP 9000)", isOn: Binding(
                    get: { appModel.isOSCEnabled },
                    set: { appModel.setOSCEnabled($0) }
                ))
                Text("Live OSC dispatch runs off the main thread; Settings only toggles the listener.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
}

// MARK: - Output

private struct SettingsOutputTab: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            settingsScopeHeader("APPLICATION")
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
                        set: { id in
                            appModel.output.selectLocalDMXDevice(
                                id: id.isEmpty ? nil : id,
                                engineRunning: appModel.performance.engineRunning
                            )
                        }
                    )) {
                        Text("None").tag("")
                        ForEach(appModel.output.availableLocalDMXDevices) { dev in
                            Text(dev.displayName).tag(dev.id)
                        }
                    }
                }
                if appModel.settings.localDMX.requestedEnabled && !appModel.output.localDMXConfiguredDeviceAvailable {
                    Text("Configured device unavailable — Local DMX stays disabled (no silent substitute).")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Toggle("Enable Local DMX", isOn: Binding(
                    get: { appModel.output.localDMXRequestedEnabled },
                    set: { on in
                        appModel.output.setLocalDMXEnabled(
                            on,
                            engineRunning: appModel.performance.engineRunning
                        )
                    }
                ))
                Text("Actual enabled: \(appModel.output.localDMXEnabled ? "yes" : "no")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Universes must be routed to Local DMX (Project section below). Protocol None sends no hardware frames even when the device is running.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                let localRouted = appModel.session.project.universes.filter { $0.protocolHint == .local || $0.protocolHint == .mirror }
                if appModel.output.localDMXEnabled && localRouted.isEmpty {
                    Text("No show universe is routed to Local DMX — enable Local DMX on a universe below or ENTTEC will stay idle.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !localRouted.isEmpty {
                    Text("Local route: \(localRouted.map { "U\($0.number)" }.joined(separator: ", ")) → ENTTEC (USB Pro framing).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Serial list shows USB-serial candidates; not all are confirmed ENTTEC. Selection prefers stable hardware identity.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section("Art-Net") {
                Toggle("Enable Art-Net", isOn: Binding(
                    get: { appModel.artNetConfig.enabled },
                    set: { appModel.setArtNetEnabled($0) }
                ))
                HStack {
                    Text("Destination")
                    Spacer()
                    TextField(
                        "host",
                        text: Binding(
                            get: { appModel.artNetConfig.destinationHost },
                            set: { appModel.setArtNetDestination($0) }
                        )
                    )
                    .frame(maxWidth: 180)
                    .multilineTextAlignment(.trailing)
                }
                Button("Art-Net Destination…") {
                    appModel.promptArtNetDestination()
                }
                .controlSize(.small)
            }
            Section("sACN") {
                Toggle("Enable sACN", isOn: Binding(
                    get: { appModel.sacnConfig.enabled },
                    set: { appModel.setSACNEnabled($0) }
                ))
                HStack {
                    Text("Unicast host (empty = multicast)")
                    Spacer()
                    TextField(
                        "host",
                        text: Binding(
                            get: { appModel.sacnConfig.destinationHost ?? "" },
                            set: { v in
                                let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
                                appModel.setSACNUnicastHost(trimmed.isEmpty ? nil : trimmed)
                            }
                        )
                    )
                    .frame(maxWidth: 180)
                    .multilineTextAlignment(.trailing)
                }
                Button("sACN Destination…") {
                    appModel.promptSACNDestination()
                }
                .controlSize(.small)
            }

            settingsScopeHeader("PROJECT")
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
            _ = prismReportCommandFailure(error, operation: "change universe route", category: .outputRouting)
        }
    }
}

// MARK: - Remote

private struct SettingsRemoteTab: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var draftPort: String = "27421"
    @State private var portError: String?

    var body: some View {
        Form {
            settingsScopeHeader("APPLICATION")
            Section("ACP remote access") {
                Text(appModel.acp.status)
                    .font(.body.monospaced())
                Text(appModel.acp.isRunning ? "Runtime: running" : "Runtime: stopped")
                    .font(.caption)
                    .foregroundStyle(appModel.acp.isRunning ? Color.secondary : Color.orange)
                if !appModel.acp.nodeID.isEmpty {
                    Text("Identity: \(appModel.acp.nodeID)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Toggle("Enable ACP remote access", isOn: Binding(
                    get: { appModel.settings.remoteAccessEnabled },
                    set: { on in
                        appModel.applyRemoteFromSettings(enabled: on)
                    }
                ))
                Toggle("Bonjour discovery", isOn: Binding(
                    get: { appModel.settings.acpDiscoveryEnabled },
                    set: { on in
                        appModel.settings.acpDiscoveryEnabled = on
                        appModel.settings.save()
                        if appModel.settings.remoteAccessEnabled {
                            appModel.applyRemoteFromSettings()
                        }
                    }
                ))
                Picker("Network scope", selection: Binding(
                    get: { appModel.settings.remoteAccessMode },
                    set: { mode in
                        appModel.settings.remoteAccessMode = mode
                        appModel.settings.save()
                        if appModel.settings.remoteAccessEnabled {
                            appModel.applyRemoteFromSettings()
                        }
                    }
                )) {
                    Text("This Mac only").tag(RemoteAccessMode.thisMacOnly)
                    Text("Local network").tag(RemoteAccessMode.localNetwork)
                }
                HStack {
                    Text("ACP WebSocket port")
                    Spacer()
                    TextField("", text: $draftPort, prompt: Text("27421"))
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { commitPort(apply: appModel.settings.remoteAccessEnabled) }
                }
                if let portError {
                    Text(portError)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }
                Button("Apply / Restart ACP") {
                    commitPort(apply: true)
                }
                .controlSize(.small)
                Divider()
                Toggle("Allow enrolled Remotes to control shows", isOn: Binding(
                    get: { appModel.settings.acpShowControlEnabled },
                    set: { enabled in
                        appModel.settings.acpShowControlEnabled = enabled
                        appModel.settings.save()
                        if appModel.settings.remoteAccessEnabled { appModel.applyRemoteFromSettings() }
                    }
                ))
                TextField("Enrolled ACP node ID", text: Binding(
                    get: { appModel.settings.acpOperatorNodeIDsText },
                    set: { appModel.settings.acpOperatorNodeIDsText = $0 }
                ))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        appModel.settings.save()
                        if appModel.settings.remoteAccessEnabled { appModel.applyRemoteFromSettings() }
                    }
                TextField("Node IDs separately authorized to clear blackout", text: Binding(
                    get: { appModel.settings.acpBlackoutClearNodeIDsText },
                    set: { appModel.settings.acpBlackoutClearNodeIDsText = $0 }
                ))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        appModel.settings.save()
                        if appModel.settings.remoteAccessEnabled { appModel.applyRemoteFromSettings() }
                    }
                Text("Show control remains unavailable until control is enabled, at least one Remote node ID is enrolled, the network scope is This Mac only, and ACP is applied/restarted. Clearing blackout requires the same node ID to be explicitly listed in the separate blackout-clear field. LAN control remains closed until ACP transport trust binds the enrolled identity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Discovery never authenticates a client. Legacy PIN/TCP/HTTP remote is removed.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section("Clients") {
                Button("Revoke all clients") {
                    appModel.kickAllRemoteClients()
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            draftPort = String(appModel.settings.acpWebSocketPort)
        }
    }

    private func commitPort(apply: Bool) {
        let parsed = AppSettingsStore.validatePort(draftPort)
        if let err = parsed.1 {
            portError = err
            return
        }
        portError = nil
        if let p = parsed.0 { appModel.settings.acpWebSocketPort = p }
        appModel.settings.save()
        if apply, appModel.settings.remoteAccessEnabled {
            appModel.applyRemoteFromSettings()
        }
    }
}

// MARK: - Advanced

private struct SettingsAdvancedTab: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            settingsScopeHeader("APPLICATION")
            Section("Plugins") {
                settingsUnavailable("Dynamic plugins are not available.")
            }
            Section("Operator diagnostics") {
                diagnosticsSummary
            }
            Section("Console") {
                Text("Validation issues: \(appModel.performance.validationIssueCount)")
                Text("Full log is available in the Console panel when shown in Build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var diagnosticsSummary: some View {
        let snap = appModel.diagnostics.snapshot
        return VStack(alignment: .leading, spacing: 6) {
            Text("Live (auto-refresh). Prefer Build → Diagnostics for the full surface.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("Engine: \(snap.engineRunning ? String(format: "running · %.0f Hz", snap.frameRateHz) : "stopped")")
            Text("Output: \(snap.outputStatusLine.isEmpty ? "—" : snap.outputStatusLine)")
                .font(.caption.monospaced())
            Text("MIDI: \(snap.midiStatus) · state \(snap.midiState)")
                .font(.caption.monospaced())
            Text("Remote: \(snap.remoteStatus)")
                .font(.caption.monospaced())
            Text(snap.remoteActuallyRunning
                 ? "Runtime running · \(snap.remoteClientCount) client(s)"
                 : "Runtime stopped · \(snap.remoteClientCount) client(s)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Local DMX \(snap.localDMXStatus) · requested \(snap.localDMXRequested ? "yes" : "no") · actual \(snap.localDMXEnabled ? "yes" : "no") · device \(snap.localDMXDeviceAvailable ? "present" : "absent")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Art-Net \(snap.artNetEnabled ? "on" : "off") · sACN \(snap.sacnEnabled ? "on" : "off")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Validation issues: \(snap.validationIssueCount)")
            if !snap.driverHealth.isEmpty {
                Divider()
                ForEach(snap.driverHealth) { row in
                    HStack {
                        Text("\(row.name) (\(row.outputProtocol))")
                        Spacer()
                        Text(row.state)
                            .foregroundStyle(row.state == "ready" ? Color.secondary : Color.orange)
                        if let err = row.lastError, !err.isEmpty {
                            Text(err).foregroundStyle(.red)
                        }
                    }
                    .font(.caption.monospaced())
                }
            }
            if !snap.universeRoutes.isEmpty {
                Divider()
                ForEach(snap.universeRoutes) { route in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("U\(route.number) \(route.name): \(route.configuredRoute)")
                            .font(.caption)
                        Text("\(route.availability) · \(route.runtimeHealth)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Logging

private struct SettingsLoggingTab: View {
    @StateObject private var model: LoggingSettingsModel

    init(initial: PrismLogConfiguration, apply: @escaping (PrismLogConfiguration) -> Void) {
        _model = StateObject(wrappedValue: LoggingSettingsModel(configuration: initial, apply: apply))
    }

    var body: some View {
        Form {
            settingsScopeHeader("APPLICATION")
            Section {
                Text("Prism writes logs through macOS Unified Logging. macOS decides how long they stay on disk. Sensitive values are redacted. Changing a level applies immediately and does not add detail to older records. Verbose and informational messages are mainly for live troubleshooting and may not persist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Profile") {
                Picker("Profile", selection: Binding(
                    get: { model.configuration.profile },
                    set: { model.applyProfile($0) }
                )) {
                    ForEach(PrismLogProfile.allCases, id: \.self) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
                Text("Custom keeps your current per-category mix. Changing any one category also selects Custom.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                HStack {
                    Button("Reset Defaults") { model.confirmReset = true }
                    Button("Set All to High-level") { model.setAll(to: .notice) }
                }
            }
            ForEach(PrismLogCategoryGroup.allCases, id: \.self) { group in
                Section(group.displayName) {
                    Button("Set all in \(group.displayName) to High-level") {
                        model.setGroup(group, to: .notice)
                    }
                    .font(.caption)
                    ForEach(group.categories, id: \.self) { category in
                        Picker(category.displayName, selection: Binding(
                            get: { model.configuration.level(for: category) },
                            set: { model.setLevel($0, for: category) }
                        )) {
                            ForEach(PrismLogLevel.settingsChoices, id: \.self) { level in
                                Text(level.settingsLabel).tag(level)
                            }
                        }
                    }
                }
            }
            Section("Support") {
                Text(model.supportCommand)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                HStack {
                    Button("Copy Support Command", action: model.copySupportCommand)
                    Button("Copy Live Stream Command", action: model.copyStreamCommand)
                }
                if let copied = model.copiedMessage {
                    Text(copied).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Reset Logging Defaults?", isPresented: $model.confirmReset) {
            Button("Reset", role: .destructive) { model.resetDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores Production Defaults for every category.")
        }
    }
}
