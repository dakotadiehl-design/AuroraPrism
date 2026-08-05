import AuroraCore
import AuroraModel
import Foundation
import SwiftUI

/// Cue list — single-click select/inspect; double-click fires (UI-02 hardening).
public struct CueListPanel: View {
    public var context: WorkspacePanelContext
    public var playbackCueIndex: Int
    public var playbackCueListID: UUID?
    public var playbackCueID: UUID?
    public var onGo: () -> Void
    public var onStop: () -> Void
    public var onBack: () -> Void
    public var onFire: (UUID) -> Void
    public var onProjectChanged: () -> Void
    public var onInspectCue: (UUID) -> Void
    public var onSelectCue: (UUID, UUID?) -> Void
    /// Bumps when document is replaced so list selection self-heals.
    public var documentEpoch: Int

    @State private var selectedListID: UUID?
    @State private var selectedCueID: UUID?

    public init(
        context: WorkspacePanelContext,
        playbackCueIndex: Int = -1,
        playbackCueListID: UUID? = nil,
        playbackCueID: UUID? = nil,
        onGo: @escaping () -> Void = {},
        onStop: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {},
        onFire: @escaping (UUID) -> Void = { _ in },
        onProjectChanged: @escaping () -> Void = {},
        onInspectCue: @escaping (UUID) -> Void = { _ in },
        onSelectCue: @escaping (UUID, UUID?) -> Void = { _, _ in },
        documentEpoch: Int = 0
    ) {
        self.context = context
        self.playbackCueIndex = playbackCueIndex
        self.playbackCueListID = playbackCueListID
        self.playbackCueID = playbackCueID
        self.onGo = onGo
        self.onStop = onStop
        self.onBack = onBack
        self.onFire = onFire
        self.onProjectChanged = onProjectChanged
        self.onInspectCue = onInspectCue
        self.onSelectCue = onSelectCue
        self.documentEpoch = documentEpoch
    }

    private var lists: [CueList] { context.project.cueLists }

    private var currentList: CueList? {
        if let selectedListID, let match = lists.first(where: { $0.id == selectedListID }) {
            return match
        }
        return lists.first
    }

    public var body: some View {
        VStack(spacing: 0) {
            transportBar
            Divider().overlay(AuroraColor.separator)
            if let list = currentList {
                if list.cues.isEmpty {
                    AuroraEmptyState(
                        title: "No cues",
                        detail: "Record looks into this list to build the show.",
                        systemImage: "list.number"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(list.cues.enumerated()), id: \.element.id) { index, cue in
                                AuroraCueRow(
                                    number: cueNumberString(cue),
                                    name: cue.name,
                                    timing: String(format: "%.1fs", cue.fadeIn),
                                    trigger: "Manual",
                                    role: role(for: index, cue: cue, list: list),
                                    onSelect: {
                                        selectCue(cue, list: list)
                                    },
                                    onDoubleClickFire: {
                                        selectCue(cue, list: list)
                                        onFire(cue.id)
                                    }
                                )
                                .contextMenu {
                                    Button("Fire Cue") {
                                        selectCue(cue, list: list)
                                        onFire(cue.id)
                                    }
                                    Button("Inspect") {
                                        selectCue(cue, list: list)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                AuroraEmptyState(
                    title: "No cue list",
                    detail: "Create a cue list to begin programming.",
                    systemImage: "list.bullet"
                )
            }
        }
        .background(AuroraColor.surfacePanel)
        .auroraDensity(.compact)
        .onAppear { healListSelection() }
        .onChange(of: documentEpoch) { _, _ in
            healListSelection()
            selectedCueID = nil
        }
        .onChange(of: lists.map(\.id)) { _, _ in
            healListSelection()
        }
    }

    private func selectCue(_ cue: Cue, list: CueList) {
        selectedCueID = cue.id
        selectedListID = list.id
        context.session.selection.selectCues([cue.id], extending: false)
        context.session.selection.selectCueLists([list.id], extending: false)
        onSelectCue(cue.id, list.id)
        onInspectCue(cue.id)
    }

    private func healListSelection() {
        if let selectedListID, lists.contains(where: { $0.id == selectedListID }) {
            return
        }
        selectedListID = lists.first?.id
        if let selectedCueID,
           currentList?.cues.contains(where: { $0.id == selectedCueID }) != true {
            self.selectedCueID = nil
        }
    }

    private var transportBar: some View {
        HStack(spacing: 8) {
            AuroraTransportButton(kind: .back, useIcon: true, action: onBack)
            AuroraTransportButton(kind: .go, useIcon: true, action: onGo)
            AuroraTransportButton(kind: .stop, useIcon: true, action: onStop)
            Spacer()
            if let playbackCueID,
               let list = currentList,
               let cue = list.cues.first(where: { $0.id == playbackCueID }) {
                Text("Playing \(cueNumberString(cue))")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            } else if playbackCueIndex >= 0 {
                Text("Playing #\(playbackCueIndex + 1)")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
        }
        .padding(8)
        .background(AuroraColor.surfaceHeader)
        .auroraDensity(.standard)
    }

    private func role(for index: Int, cue: Cue, list: CueList) -> AuroraCueRowRole {
        if selectedCueID == cue.id { return .selected }
        if let playbackCueID, cue.id == playbackCueID { return .current }
        if let playbackCueListID, list.id == playbackCueListID, index == playbackCueIndex {
            return .current
        }
        if let playbackCueListID, list.id == playbackCueListID,
           playbackCueIndex >= 0, index == playbackCueIndex + 1 {
            return .next
        }
        return .normal
    }

    private func cueNumberString(_ cue: Cue) -> String {
        NSDecimalNumber(decimal: cue.number).stringValue
    }
}
