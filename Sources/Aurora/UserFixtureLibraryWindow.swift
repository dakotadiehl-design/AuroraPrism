import AuroraDesignSystem
import AppKit
import AuroraDiagnostics
import AuroraModel
import AuroraUI
import SwiftUI

struct UserFixtureLibraryWindow: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var searchText = ""
    @State private var pendingRemoval: [FixtureDefinition] = []
    @State private var errorReport: PrismErrorReport?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("User Fixture Library")
                    .font(.title2.weight(.semibold))
                Text("\(appModel.document.userFixtureDefinitions.count) modes")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Create Fixture…") {
                    NotificationCenter.default.post(name: .openFixtureCreator, object: nil)
                }
                Button("Import…") { appModel.importFixtureDefinition() }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([appModel.document.userFixtureLibraryDirectory])
                }
                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload User Library")
            }
            .padding(16)

            Divider()

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search manufacturers, fixtures, and modes", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(9)
            .background(AuroraColor.surfaceWell)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(12)

            if families.isEmpty {
                AuroraEmptyState(
                    title: searchText.isEmpty ? "User Library Is Empty" : "No Matching Fixtures",
                    detail: searchText.isEmpty
                        ? "Import a fixture definition to make it available to every show."
                        : "Try a different manufacturer, fixture, or mode name.",
                    systemImage: "books.vertical"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(families) { family in
                            familyCard(family)
                        }
                    }
                    .padding(12)
                }
            }

            Divider()
            Text(appModel.document.userFixtureLibraryDirectory.path)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(AuroraColor.surfacePanel)
        .confirmationDialog(
            pendingRemoval.count > 1 ? "Remove Fixture Profile?" : "Remove Fixture Mode?",
            isPresented: Binding(
                get: { !pendingRemoval.isEmpty },
                set: { if !$0 { pendingRemoval = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button(pendingRemoval.count > 1 ? "Remove Entire Profile" : "Remove Mode", role: .destructive) {
                removePending()
            }
            Button("Cancel", role: .cancel) { pendingRemoval = [] }
        } message: {
            Text("This removes the selected item from your User Library. Existing projects retain their embedded fixture definitions.")
        }
        .prismErrorAlert(item: $errorReport)
    }

    private var families: [UserFixtureFamily] {
        let grouped = Dictionary(grouping: appModel.document.userFixtureDefinitions) {
            normalized($0.manufacturer) + "\u{1f}" + normalized($0.model)
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return grouped.compactMap { key, modes -> UserFixtureFamily? in
            guard let first = modes.first else { return nil }
            guard query.isEmpty || modes.contains(where: {
                $0.manufacturer.localizedCaseInsensitiveContains(query)
                    || $0.model.localizedCaseInsensitiveContains(query)
                    || $0.modeName.localizedCaseInsensitiveContains(query)
            }) else { return nil }
            return UserFixtureFamily(
                id: key,
                manufacturer: first.manufacturer.isEmpty ? "Generic" : first.manufacturer,
                model: first.model,
                modes: modes.sorted {
                    let order = $0.modeName.localizedStandardCompare($1.modeName)
                    return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
                }
            )
        }.sorted {
            let manufacturer = $0.manufacturer.localizedStandardCompare($1.manufacturer)
            if manufacturer != .orderedSame { return manufacturer == .orderedAscending }
            return $0.model.localizedStandardCompare($1.model) == .orderedAscending
        }
    }

    private func familyCard(_ family: UserFixtureFamily) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(family.model).font(.headline)
                    Text(family.manufacturer).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Remove Profile…", role: .destructive) { pendingRemoval = family.modes }
                    .controlSize(.small)
            }
            Divider()
            ForEach(family.modes) { mode in
                HStack {
                    Text(mode.modeName)
                    Spacer()
                    Text("\(max(mode.channelCount, mode.calculatedFootprint)) channels")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) { pendingRemoval = [mode] } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this mode")
                }
            }
        }
        .padding(12)
        .background(AuroraColor.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AuroraColor.separator))
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    private func reload() {
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
                    fallbackMessage: "The Fixture Library could not be updated."
                )
            )
        }
    }

    private func removePending() {
        let ids = Set(pendingRemoval.map(\.id))
        pendingRemoval = []
        do {
            try appModel.document.removeUserFixtureDefinitions(ids)
            appModel.notifyUI()
        } catch {
            errorReport = PrismErrorReporting.report(
                error: error,
                context: PrismErrorContext(
                    operation: "remove user fixture",
                    category: .fixtureLibrary,
                    fallbackTitle: "Prism Couldn't Update the Fixture Library",
                    fallbackMessage: "The Fixture Library could not be updated."
                )
            )
        }
    }
}

private struct UserFixtureFamily: Identifiable {
    let id: String
    let manufacturer: String
    let model: String
    let modes: [FixtureDefinition]
}
