import AppKit
import AuroraFixtureLib
import AuroraModel
import AuroraUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LightKeyFixtureImporterViewModel: ObservableObject {
    enum Phase: Equatable {
        case empty
        case reading(String)
        case review
        case importing
        case completed(Int)
        case failed(String)
    }

    @Published var phase: Phase = .empty
    @Published var result: LightKeyImportResult?
    @Published var selectedCandidateIDs = Set<UUID>()
    @Published var selectedCandidateID: UUID?
    @Published var selectedChannelID: UUID?
    @Published var alsoSaveToUserLibrary = false
    @Published var acknowledgedReviewIssues = false

    var selectedCandidate: LightKeyImportCandidate? {
        guard let selectedCandidateID else { return result?.candidates.first }
        return result?.candidates.first { $0.id == selectedCandidateID }
    }

    var selectedChannel: ChannelDef? {
        guard let selectedChannelID else { return selectedCandidate?.definition.channels.first }
        return selectedCandidate?.definition.channels.first { $0.id == selectedChannelID }
    }

    var selectedChannelSource: LightKeyChannelSource? {
        guard let selectedChannel else { return nil }
        return selectedCandidate?.channelSources.first { $0.channelID == selectedChannel.id }
    }

    var selectedDefinitions: [FixtureDefinition] {
        result?.candidates.filter { selectedCandidateIDs.contains($0.id) }.map(\.definition) ?? []
    }

    var selectedIssues: [FixtureImportIssue] {
        result?.candidates.filter { selectedCandidateIDs.contains($0.id) }.flatMap(\.issues) ?? []
    }

    var canImport: Bool {
        phase == .review
            && !selectedDefinitions.isEmpty
            && !selectedIssues.contains { $0.severity == .fatal }
            && (!selectedIssues.contains { $0.severity == .requiresReview } || acknowledgedReviewIssues)
    }

    var showsImportButton: Bool {
        if case .review = phase { return true }
        return false
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose LightKey Fixture"
        panel.message = "Select a LightKey fixture profile to inspect before importing into Prism."
        panel.prompt = "Inspect"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let lightKeyType = UTType(filenameExtension: "lightkeyfxt") {
            panel.allowedContentTypes = [lightKeyType]
        } else {
            panel.allowedContentTypes = [.data]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    func load(url: URL) {
        phase = .reading(url.lastPathComponent)
        result = nil
        selectedCandidateIDs = []
        selectedCandidateID = nil
        selectedChannelID = nil
        acknowledgedReviewIssues = false
        Task {
            do {
                let imported = try await Task.detached(priority: .userInitiated) {
                    try LightKeyFixtureImporter.inspect(url: url)
                }.value
                result = imported
                selectedCandidateIDs = Set(imported.candidates.filter { !$0.hasFatalIssues }.map(\.id))
                selectedCandidateID = imported.candidates.first?.id
                selectedChannelID = imported.candidates.first?.definition.channels.first?.id
                phase = .review
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func selectCandidate(_ id: UUID) {
        selectedCandidateID = id
        selectedChannelID = result?.candidates.first(where: { $0.id == id })?.definition.channels.first?.id
    }

    func toggleCandidate(_ id: UUID) {
        if selectedCandidateIDs.contains(id) {
            selectedCandidateIDs.remove(id)
        } else if let candidate = result?.candidates.first(where: { $0.id == id }), !candidate.hasFatalIssues {
            selectedCandidateIDs.insert(id)
        }
        acknowledgedReviewIssues = false
    }

    func importSelected(using appModel: AppModel) {
        guard canImport, let result else { return }
        phase = .importing
        do {
            let count = try appModel.importLightKeyFixtureDefinitions(
                selectedDefinitions,
                sourceName: result.sourceURL.lastPathComponent
            )
            if alsoSaveToUserLibrary {
                for definition in selectedDefinitions {
                    _ = try UserFixtureLibrary.save(definition: definition)
                }
            }
            phase = .completed(count)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func reset() {
        phase = .empty
        result = nil
        selectedCandidateIDs = []
        selectedCandidateID = nil
        selectedChannelID = nil
        acknowledgedReviewIssues = false
    }
}

struct LightKeyFixtureImporterWindowRoot: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var model = LightKeyFixtureImporterViewModel()

    var body: some View {
        AuroraTokens.shellBackground {
            VStack(spacing: 0) {
                header
                Divider().overlay(AuroraColor.separatorStrong)
                content
                Divider().overlay(AuroraColor.separatorStrong)
                footer
            }
        }
        .buttonStyle(AuroraButtonStyle())
        .frame(minWidth: 850, minHeight: 560)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil, perform: acceptDrop)
    }

    private var header: some View {
        HStack(spacing: AuroraSpacing.md) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AuroraColor.accentBright)
            VStack(alignment: .leading, spacing: 2) {
                Text("LIGHTKEY FIXTURE IMPORTER")
                    .font(AuroraTypography.windowTitle)
                    .foregroundStyle(AuroraColor.textPrimary)
                Text(headerDetail)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
            Spacer()
            if model.result != nil {
                AuroraButton("Choose Another…", kind: .secondary) { model.chooseFile() }
            }
        }
        .padding(.horizontal, AuroraSpacing.lg)
        .frame(height: 58)
        .background(AuroraColor.surfaceHeader)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .empty:
            emptyState
        case .reading(let filename):
            progressState("Reading \(filename)…")
        case .review, .importing:
            reviewWorkspace
        case .completed(let count):
            completionState(count)
        case .failed(let message):
            failureState(message)
        }
    }

    private var emptyState: some View {
        VStack(spacing: AuroraSpacing.lg) {
            Image(systemName: "lightbulb.led.wide")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(AuroraColor.accentBright)
            Text("Import a LightKey fixture profile")
                .font(AuroraTypography.panelTitle)
                .foregroundStyle(AuroraColor.textPrimary)
            Text("Prism reads the fixture as data, validates every personality, and lets you review channels before anything is added to the show. You can also drop a .lightkeyfxt file here.")
                .font(AuroraTypography.secondary)
                .foregroundStyle(AuroraColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            AuroraButton("Choose LightKey Fixture…", kind: .primary) { model.chooseFile() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuroraColor.surfaceWorkspace)
    }

    private var reviewWorkspace: some View {
        HSplitView {
            sourceColumn.frame(minWidth: 205, idealWidth: 230, maxWidth: 280)
            channelColumn.frame(minWidth: 420)
            inspectorColumn.frame(minWidth: 230, idealWidth: 275, maxWidth: 340)
        }
        .background(AuroraColor.surfaceWorkspace)
        .disabled(model.phase == .importing)
    }

    private var sourceColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("SOURCE")
            if let result = model.result {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.manufacturer).font(AuroraTypography.primaryValue)
                    Text(result.model).font(AuroraTypography.secondary)
                    Text(result.sourceURL.lastPathComponent).font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textTertiary).lineLimit(2)
                    if let beams = result.numberOfBeams {
                        Text("\(beams) beams" + (result.beamSpreadDegrees.map { " · \($0.formatted())°" } ?? ""))
                            .font(AuroraTypography.metadata).foregroundStyle(AuroraColor.textSecondary)
                    }
                }
                .padding(AuroraSpacing.md)
            }
            Divider().overlay(AuroraColor.separator)
            sectionHeader("PERSONALITIES")
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.result?.candidates ?? []) { candidate in
                        personalityRow(candidate)
                    }
                }
                .padding(6)
            }
        }
        .background(AuroraColor.surfacePanel)
    }

    private func personalityRow(_ candidate: LightKeyImportCandidate) -> some View {
        let selected = model.selectedCandidateID == candidate.id
        return HStack(spacing: 7) {
            Button { model.toggleCandidate(candidate.id) } label: {
                Image(systemName: model.selectedCandidateIDs.contains(candidate.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(candidate.hasFatalIssues ? AuroraColor.disabled : AuroraColor.accentBright)
            }
            .buttonStyle(.plain)
            .disabled(candidate.hasFatalIssues)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.definition.modeName).font(AuroraTypography.tableCell)
                Text("\(candidate.definition.channelCount) channels")
                    .font(AuroraTypography.metadata).foregroundStyle(AuroraColor.textTertiary)
            }
            Spacer()
            if !candidate.issues.isEmpty {
                Image(systemName: candidate.hasFatalIssues ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(candidate.hasFatalIssues ? AuroraColor.critical : AuroraColor.warning)
                    .help(issueTooltip(candidate.issues))
            }
        }
        .padding(.horizontal, 8).frame(height: 42)
        .background(selected ? AuroraColor.surfaceSelected : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AuroraMetrics.radiusTight))
        .contentShape(Rectangle())
        .onTapGesture { model.selectCandidate(candidate.id) }
    }

    private var channelColumn: some View {
        VStack(spacing: 0) {
            sectionHeader(model.selectedCandidate?.definition.modeName.uppercased() ?? "CHANNELS")
            HStack(spacing: 0) {
                tableHeader("DMX", width: 48)
                tableHeader("CHANNEL", width: nil)
                tableHeader("ATTRIBUTE", width: 120)
                tableHeader("RES", width: 62)
                tableHeader("FX", width: 38)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.selectedCandidate?.definition.channels ?? []) { channel in
                        channelRow(channel)
                    }
                }
            }
        }
        .background(AuroraColor.surfacePanel)
    }

    private func channelRow(_ channel: ChannelDef) -> some View {
        let selected = model.selectedChannelID == channel.id
        let issues = issues(for: channel)
        return HStack(spacing: 0) {
            tableCell("\(channel.offset)", width: 48, monospaced: true)
            tableCell(channel.name, width: nil)
            HStack(spacing: 5) {
                Text(channel.attribute)
                    .font(AuroraTypography.metadata.monospaced())
                    .foregroundStyle(AuroraColor.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if !issues.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AuroraColor.warning)
                        .help(unsupportedAttributeTooltip(channel: channel, issues: issues))
                        .accessibilityLabel("Unsupported LightKey attribute details")
                }
            }
            .padding(.horizontal, 6)
            .frame(minWidth: 120, maxWidth: 120, alignment: .leading)
            tableCell(resolutionLabel(channel.resolution), width: 62, monospaced: true)
            tableCell("\(channel.dmxFunctions.count)", width: 38, monospaced: true)
        }
        .frame(height: AuroraMetrics.tableRowHeight)
        .background(selected ? AuroraColor.surfaceSelected : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedChannelID = channel.id }
    }

    private var inspectorColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AuroraSpacing.md) {
                sectionHeader("INSPECTOR")
                if let channel = model.selectedChannel {
                    inspectorValue("CHANNEL", "\(channel.offset) · \(channel.name)")
                    inspectorValue("PRISM ATTRIBUTE", channel.attribute)
                    inspectorValue("RESOLUTION", resolutionLabel(channel.resolution))
                    if let source = model.selectedChannelSource {
                        inspectorValue("LIGHTKEY CLASS", source.capabilityClasses.joined(separator: "\n"))
                        if !source.beamIndexes.isEmpty {
                            inspectorValue("BEAMS", source.beamIndexes.map(String.init).joined(separator: ", "))
                        }
                    }
                    if !channel.dmxFunctions.isEmpty {
                        Text("DMX FUNCTIONS").font(AuroraTypography.controlLabel)
                            .foregroundStyle(AuroraColor.textTertiary)
                        ForEach(channel.dmxFunctions) { function in
                            HStack(alignment: .top) {
                                Text("\(function.dmxMin)–\(function.dmxMax)")
                                    .font(AuroraTypography.metadata.monospacedDigit())
                                    .foregroundStyle(AuroraColor.accentBright)
                                    .frame(width: 52, alignment: .leading)
                                Text(function.name).font(AuroraTypography.metadata)
                                    .foregroundStyle(AuroraColor.textSecondary)
                            }
                        }
                    }
                }
                if let candidate = model.selectedCandidate, !candidate.issues.isEmpty {
                    Divider().overlay(AuroraColor.separator)
                    Text("IMPORT ISSUES").font(AuroraTypography.controlLabel)
                        .foregroundStyle(AuroraColor.textTertiary)
                    ForEach(candidate.issues) { issue in issueView(issue) }
                }
            }
            .padding(.bottom, AuroraSpacing.lg)
        }
        .background(AuroraColor.surfacePanel)
    }

    private var footer: some View {
        HStack(spacing: AuroraSpacing.md) {
            if case .review = model.phase {
                Toggle("Also save to User Fixture Library", isOn: $model.alsoSaveToUserLibrary)
                    .toggleStyle(.checkbox).font(AuroraTypography.metadata)
                if model.selectedIssues.contains(where: { $0.severity == .requiresReview }) {
                    Toggle("I reviewed flagged mappings", isOn: $model.acknowledgedReviewIssues)
                        .toggleStyle(.checkbox).font(AuroraTypography.metadata)
                }
            }
            Spacer()
            footerStatus
            if model.showsImportButton {
                AuroraButton("Import Selected", kind: .primary, isEnabled: model.canImport) {
                    model.importSelected(using: appModel)
                }
            }
        }
        .padding(.horizontal, AuroraSpacing.lg)
        .frame(height: 52)
        .background(AuroraColor.surfaceHeader)
    }

    @ViewBuilder private var footerStatus: some View {
        switch model.phase {
        case .review:
            Text("\(model.selectedDefinitions.count) selected")
        case .importing:
            ProgressView().controlSize(.small); Text("Importing…")
        case .completed(let count):
            Text("Imported \(count) personalities")
        case .failed:
            Text("Import failed").foregroundStyle(AuroraColor.critical)
        default:
            EmptyView()
        }
    }

    private func progressState(_ title: String) -> some View {
        VStack(spacing: AuroraSpacing.md) { ProgressView(); Text(title).font(AuroraTypography.secondary) }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(AuroraColor.surfaceWorkspace)
    }

    private func completionState(_ count: Int) -> some View {
        VStack(spacing: AuroraSpacing.lg) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(AuroraColor.success)
            Text("Import complete").font(AuroraTypography.panelTitle)
            Text("Prism added \(count) fixture personalities to the current show.")
                .font(AuroraTypography.secondary).foregroundStyle(AuroraColor.textSecondary)
            AuroraButton("Import Another", kind: .primary) { model.reset() }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(AuroraColor.surfaceWorkspace)
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: AuroraSpacing.lg) {
            Image(systemName: "xmark.octagon.fill").font(.system(size: 48)).foregroundStyle(AuroraColor.critical)
            Text("Couldn’t import the fixture").font(AuroraTypography.panelTitle)
            Text(message).font(AuroraTypography.secondary).foregroundStyle(AuroraColor.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 540)
            HStack {
                AuroraButton("Start Over", kind: .secondary) { model.reset() }
                AuroraButton("Choose Another…", kind: .primary) { model.chooseFile() }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(AuroraColor.surfaceWorkspace)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(AuroraTypography.sectionHeading).foregroundStyle(AuroraColor.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
            .frame(height: AuroraMetrics.panelHeaderHeight).background(AuroraColor.surfaceHeader)
    }

    private func tableHeader(_ title: String, width: CGFloat?) -> some View {
        Text(title).font(AuroraTypography.controlLabel).foregroundStyle(AuroraColor.textTertiary)
            .frame(minWidth: width, maxWidth: width ?? .infinity, alignment: .leading)
            .padding(.horizontal, 6).frame(height: AuroraMetrics.tableHeaderHeight)
            .background(AuroraColor.surfaceWell)
    }

    private func tableCell(_ text: String, width: CGFloat?, monospaced: Bool = false) -> some View {
        Text(text).font(monospaced ? AuroraTypography.metadata.monospaced() : AuroraTypography.tableCell)
            .foregroundStyle(AuroraColor.textSecondary).lineLimit(1)
            .frame(minWidth: width, maxWidth: width ?? .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }

    private func inspectorValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(AuroraTypography.controlLabel).foregroundStyle(AuroraColor.textTertiary)
            Text(value).font(AuroraTypography.metadata).foregroundStyle(AuroraColor.textSecondary)
                .textSelection(.enabled)
        }.padding(.horizontal, 10)
    }

    private func issueView(_ issue: FixtureImportIssue) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: issue.severity == .fatal ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .fatal ? AuroraColor.critical : AuroraColor.warning)
            Text(issue.message).font(AuroraTypography.metadata).foregroundStyle(AuroraColor.textSecondary)
        }
        .padding(.horizontal, 10)
        .help(issueTooltip([issue]))
    }

    private func issues(for channel: ChannelDef) -> [FixtureImportIssue] {
        model.selectedCandidate?.issues.filter {
            $0.channelOffset == channel.offset
                && [.unknownCapability, .unknownColorEmitter, .conditionalCapability, .compoundChannel, .unsafeCommand]
                    .contains($0.code)
        } ?? []
    }

    private func unsupportedAttributeTooltip(
        channel: ChannelDef,
        issues: [FixtureImportIssue]
    ) -> String {
        let sourceClasses = model.selectedCandidate?.channelSources
            .first(where: { $0.channelID == channel.id })?.capabilityClasses ?? []
        let source = sourceClasses.isEmpty ? channel.name : sourceClasses.joined(separator: ", ")
        let details = issueTooltip(issues)
        return "LightKey attribute: \(source)\nPrism mapping: \(channel.attribute)\n\n\(details)"
    }

    private func issueTooltip(_ issues: [FixtureImportIssue]) -> String {
        issues.map { issue in
            let channel = issue.channelOffset.map { "Channel \($0): " } ?? ""
            return channel + issue.message
        }.joined(separator: "\n\n")
    }

    private func resolutionLabel(_ resolution: ChannelResolution) -> String {
        switch resolution { case .eightBit: return "8-bit"; case .coarse: return "coarse"; case .fine: return "fine" }
    }

    private var headerDetail: String {
        model.result.map { "\($0.manufacturer) · \($0.model)" } ?? "Review LightKey personalities before adding them to Prism"
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else { url = item as? URL }
            guard let url, url.pathExtension.lowercased() == "lightkeyfxt" else { return }
            Task { @MainActor in model.load(url: url) }
        }
        return true
    }
}
