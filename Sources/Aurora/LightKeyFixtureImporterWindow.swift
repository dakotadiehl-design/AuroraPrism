import AuroraDesignSystem
import AppKit
import AuroraDiagnostics
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
    @Published var results: [LightKeyImportResult] = []
    @Published var batchFailures: [LightKeyBatchImportFailure] = []
    @Published var sourceURL: URL?
    @Published var sourceURLs: [URL] = []
    @Published var selectedCandidateIDs = Set<UUID>()
    @Published var selectedCandidateID: UUID?
    @Published var selectedChannelID: UUID?
    @Published var alsoSaveToUserLibrary = false
    @Published var acknowledgedReviewIssues = false
    @Published var warningExportStatus: String?

    var allCandidates: [LightKeyImportCandidate] { results.flatMap(\.candidates) }
    var allIssues: [FixtureImportIssue] { allCandidates.flatMap(\.issues) }

    var result: LightKeyImportResult? {
        if let selectedCandidateID {
            return results.first { result in result.candidates.contains { $0.id == selectedCandidateID } }
        }
        return results.first
    }

    var selectedCandidate: LightKeyImportCandidate? {
        guard let selectedCandidateID else { return allCandidates.first }
        return allCandidates.first { $0.id == selectedCandidateID }
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
        allCandidates.filter { selectedCandidateIDs.contains($0.id) }.map(\.definition)
    }

    var selectedIssues: [FixtureImportIssue] {
        allCandidates.filter { selectedCandidateIDs.contains($0.id) }.flatMap(\.issues)
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

    var hasExportableWarnings: Bool {
        !batchFailures.isEmpty || allCandidates.contains { !$0.issues.isEmpty }
    }

    func chooseSource() {
        let panel = NSOpenPanel()
        panel.title = "Choose LightKey Fixture or Folder"
        panel.message = "Select one or more LightKey fixtures or folders. Hold Command or Control to select multiple items. Prism searches folders recursively."
        panel.prompt = "Inspect"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if let lightKeyType = UTType(filenameExtension: "lightkeyfxt") {
            panel.allowedContentTypes = [lightKeyType]
        } else {
            panel.allowedContentTypes = [.data]
        }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        load(sourceURLs: panel.urls)
    }

    func load(sourceURL: URL) {
        load(sourceURLs: [sourceURL])
    }

    func load(sourceURLs: [URL]) {
        let sourceURLs = Array(Dictionary(grouping: sourceURLs, by: \.standardizedFileURL).keys)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !sourceURLs.isEmpty else { return }
        phase = .reading(sourceURLs.count == 1 ? sourceURLs[0].lastPathComponent : "\(sourceURLs.count) selections")
        self.sourceURLs = sourceURLs
        sourceURL = sourceURLs.first
        results = []
        batchFailures = []
        selectedCandidateIDs = []
        selectedCandidateID = nil
        selectedChannelID = nil
        acknowledgedReviewIssues = false
        warningExportStatus = nil
        Task {
            do {
                let batches = try await Task.detached(priority: .userInitiated) {
                    try sourceURLs.map {
                        try LightKeyFixtureImporter.inspectRecursively(sourceURL: $0)
                    }
                }.value
                let fixtures = batches.flatMap(\.fixtures)
                let failures = batches.flatMap(\.failures)
                let uniqueFixtures = Dictionary(grouping: fixtures, by: { $0.sourceURL.standardizedFileURL })
                    .compactMap { $0.value.first }
                    .sorted { $0.sourceURL.path.localizedStandardCompare($1.sourceURL.path) == .orderedAscending }
                guard !uniqueFixtures.isEmpty else {
                    if failures.isEmpty {
                        phase = .failed("Those selections do not contain any .lightkeyfxt files.")
                    } else {
                        phase = .failed("Prism could not read any LightKey fixtures in those selections.\n\n" + failures.map {
                            "\($0.sourceURL.lastPathComponent): \($0.message)"
                        }.joined(separator: "\n"))
                    }
                    return
                }
                results = uniqueFixtures
                batchFailures = failures
                let candidates = uniqueFixtures.flatMap(\.candidates)
                selectedCandidateIDs = Set(candidates.filter { !$0.hasFatalIssues }.map(\.id))
                selectedCandidateID = candidates.first?.id
                selectedChannelID = candidates.first?.definition.channels.first?.id
                phase = .review
            } catch {
                phase = .failed(
                    PrismErrorReporting.report(
                        error: error,
                        context: PrismErrorContext(
                            operation: "inspect LightKey fixture",
                            category: .fixtureLightkey,
                            fallbackTitle: "Prism Couldn't Import That LightKey Fixture",
                            fallbackMessage: "Prism couldn’t read that LightKey fixture.",
                            eventCode: "fixture.lightkey.import_failed"
                        )
                    ).userMessage
                )
            }
        }
    }

    func selectCandidate(_ id: UUID) {
        selectedCandidateID = id
        selectedChannelID = allCandidates.first(where: { $0.id == id })?.definition.channels.first?.id
    }

    func toggleCandidate(_ id: UUID) {
        if selectedCandidateIDs.contains(id) {
            selectedCandidateIDs.remove(id)
        } else if let candidate = allCandidates.first(where: { $0.id == id }), !candidate.hasFatalIssues {
            selectedCandidateIDs.insert(id)
        }
        acknowledgedReviewIssues = false
    }

    func importSelected(using appModel: AppModel) {
        guard canImport else { return }
        phase = .importing
        do {
            let count = try appModel.importLightKeyFixtureDefinitions(
                selectedDefinitions,
                sourceName: sourceURLs.count == 1 ? sourceURLs[0].lastPathComponent : "LightKey batch (\(sourceURLs.count) selections)"
            )
            if alsoSaveToUserLibrary {
                for definition in selectedDefinitions {
                    _ = try UserFixtureLibrary.save(definition: definition)
                }
            }
            phase = .completed(count)
        } catch {
            phase = .failed(
                PrismErrorReporting.report(
                    error: error,
                    context: PrismErrorContext(
                        operation: "import LightKey fixture",
                        category: .fixtureLightkey,
                        fallbackTitle: "Prism Couldn't Import That LightKey Fixture",
                        fallbackMessage: "Prism couldn’t import that LightKey fixture.",
                        eventCode: "fixture.lightkey.import_failed"
                    )
                ).userMessage
            )
        }
    }

    func exportWarnings() {
        guard hasExportableWarnings else { return }

        let panel = NSSavePanel()
        panel.title = "Export LightKey Import Warnings"
        panel.message = "Save the complete LightKey fixture import warning report as a text file."
        panel.prompt = "Export"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = warningReportFilename
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try warningReport.write(to: destination, atomically: true, encoding: .utf8)
            warningExportStatus = "Warnings exported to \(destination.lastPathComponent)"
        } catch {
            warningExportStatus = "Couldn’t export warnings: \(error.localizedDescription)"
        }
    }

    func reset() {
        phase = .empty
        results = []
        batchFailures = []
        sourceURL = nil
        sourceURLs = []
        selectedCandidateIDs = []
        selectedCandidateID = nil
        selectedChannelID = nil
        acknowledgedReviewIssues = false
        warningExportStatus = nil
    }

    private var warningReportFilename: String {
        let sourceName = sourceURLs.count > 1
            ? "LightKey Batch"
            : (sourceURL?.deletingPathExtension().lastPathComponent ?? "LightKey Import")
        let invalidCharacters = CharacterSet.alphanumerics.inverted
        let safeName = sourceName.components(separatedBy: invalidCharacters)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(safeName.isEmpty ? "LightKey-Import" : safeName)-warnings.txt"
    }

    private var warningReport: String {
        var lines = [
            "Prism LightKey Fixture Import Warnings",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "Sources: \(sourceURLs.count)",
            "Fixtures read: \(results.count)",
            "Personalities inspected: \(allCandidates.count)",
            "Import issues: \(allIssues.count)",
            ""
        ]
        lines.insert(contentsOf: sourceURLs.map { "- \($0.path)" }, at: 3)

        if !allIssues.isEmpty {
            lines.append("SUMMARY BY SEVERITY")
            for severity in FixtureImportIssueSeverity.allCases {
                let count = allIssues.count { $0.severity == severity }
                if count > 0 { lines.append("- \(severity.rawValue): \(count)") }
            }
            lines.append("")
            lines.append("SUMMARY BY CODE")
            for entry in Dictionary(grouping: allIssues, by: \.code)
                .map({ ($0.key.rawValue, $0.value.count) })
                .sorted(by: { $0.0 < $1.0 }) {
                lines.append("- \(entry.0): \(entry.1)")
            }
            lines.append("")
        }

        if !batchFailures.isEmpty {
            lines.append("FILES THAT COULD NOT BE READ (\(batchFailures.count))")
            for failure in batchFailures {
                lines.append("- File: \(failure.sourceURL.path)")
                lines.append("  Error: \(failure.message)")
            }
            lines.append("")
        }

        let candidatesWithIssues = results.flatMap { result in
            result.candidates.filter { !$0.issues.isEmpty }.map { (result, $0) }
        }
        lines.append("FIXTURE IMPORT WARNINGS (\(candidatesWithIssues.reduce(0) { $0 + $1.1.issues.count }))")
        if candidatesWithIssues.isEmpty {
            lines.append("None")
        } else {
            for (result, candidate) in candidatesWithIssues {
                lines.append("")
                lines.append("Fixture: \(result.manufacturer) \(result.model)")
                lines.append("File: \(result.sourceURL.path)")
                lines.append("Personality: \(candidate.definition.modeName) (\(candidate.definition.channelCount) channels)")
                for issue in candidate.issues {
                    let severity = issue.severity.rawValue
                        .replacingOccurrences(of: "requiresReview", with: "requires review")
                        .uppercased()
                    let channel = issue.channelOffset.map { " | Channel \($0)" } ?? ""
                    lines.append("- [\(severity)] [\(issue.code.rawValue)]\(channel) \(issue.message)")
                }
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
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
            if !model.results.isEmpty {
                AuroraButton("Choose Another…", kind: .secondary) { model.chooseSource() }
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
            Text("Import LightKey fixture profiles")
                .font(AuroraTypography.panelTitle)
                .foregroundStyle(AuroraColor.textPrimary)
            Text("Choose one or more .lightkeyfxt files or folders. Hold Command or Control to select multiple items. Prism searches folders recursively, validates every personality, and lets you review the batch before anything is added to the show. You can also drop a fixture or folder here.")
                .font(AuroraTypography.secondary)
                .foregroundStyle(AuroraColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            AuroraButton("Choose Fixture or Folder…", kind: .primary) { model.chooseSource() }
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
            VStack(alignment: .leading, spacing: 4) {
                Text(model.sourceURLs.count > 1 ? "\(model.sourceURLs.count) selected items" : (model.sourceURL?.lastPathComponent ?? "LightKey Import"))
                    .font(AuroraTypography.primaryValue)
                Text("\(model.results.count) fixtures · \(model.allCandidates.count) personalities")
                    .font(AuroraTypography.metadata).foregroundStyle(AuroraColor.textSecondary)
                if !model.batchFailures.isEmpty {
                    Label("\(model.batchFailures.count) files could not be read", systemImage: "exclamationmark.triangle.fill")
                        .font(AuroraTypography.metadata).foregroundStyle(AuroraColor.warning)
                        .help(model.batchFailures.map {
                            "\($0.sourceURL.lastPathComponent): \($0.message)"
                        }.joined(separator: "\n\n"))
                }
            }
            .padding(AuroraSpacing.md)
            Divider().overlay(AuroraColor.separator)
            sectionHeader("PERSONALITIES")
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.results, id: \.sourceURL) { result in
                        VStack(spacing: 2) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(result.manufacturer) · \(result.model)")
                                    .font(AuroraTypography.controlLabel)
                                    .foregroundStyle(AuroraColor.textSecondary)
                                Text(result.sourceURL.lastPathComponent)
                                    .font(AuroraTypography.metadata)
                                    .foregroundStyle(AuroraColor.textTertiary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.top, 5)
                            ForEach(result.candidates) { candidate in
                                personalityRow(candidate)
                            }
                        }
                        .padding(.bottom, 4)
                        .background(AuroraColor.surfaceWell.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: AuroraMetrics.radiusTight))
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
                                if let attribute = function.attribute {
                                    Text(attribute)
                                        .font(AuroraTypography.metadata.monospaced())
                                        .foregroundStyle(AuroraColor.textTertiary)
                                }
                                if function.isProtected {
                                    Image(systemName: "lock.shield.fill")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(AuroraColor.warning)
                                        .help(protectedFunctionTooltip(function))
                                        .accessibilityLabel("Protected fixture command")
                                }
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
            if model.hasExportableWarnings {
                AuroraButton("Export Warnings…", kind: .secondary) {
                    model.exportWarnings()
                }
            }
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
            Text(model.warningExportStatus ?? "\(model.selectedDefinitions.count) selected")
        case .importing:
            ProgressView().controlSize(.small); Text("Importing…")
        case .completed(let count):
            Text(model.warningExportStatus ?? "Imported \(count) personalities")
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
                AuroraButton("Choose Another…", kind: .primary) { model.chooseSource() }
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

    private func protectedFunctionTooltip(_ function: DMXFunctionRange) -> String {
        let category = function.commandCategory?.rawValue ?? "custom"
        let duration = function.holdDurationMilliseconds.map { " Hold for at least \($0) ms." } ?? ""
        return "Protected \(category) command. Prism excludes this DMX range from normal Programmer, cue, and effect output. Explicit confirmation is required.\(duration)"
    }

    private func resolutionLabel(_ resolution: ChannelResolution) -> String {
        switch resolution { case .eightBit: return "8-bit"; case .coarse: return "coarse"; case .fine: return "fine" }
    }

    private var headerDetail: String {
        if model.results.count > 1 {
            return "Reviewing \(model.results.count) LightKey fixtures · \(model.allCandidates.count) personalities"
        }
        return model.result.map { "\($0.manufacturer) · \($0.model)" }
            ?? "Review LightKey personalities before adding them to Prism"
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else { url = item as? URL }
            guard let url else { return }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true || url.pathExtension.lowercased() == "lightkeyfxt" else { return }
            Task { @MainActor in model.load(sourceURL: url) }
        }
        return true
    }
}
