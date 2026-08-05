import AppKit
import AuroraCore
import SwiftUI

/// Multi-pane workspace host (SwiftUI splits — pragmatic docking v1).
public struct WorkspaceView: View {
    @Binding public var layout: WorkspaceLayout
    public var context: WorkspacePanelContext
    /// Optional override for panel bodies (PR8 injects real patch/browser).
    public var panelBuilder: (WorkspacePanelID, WorkspacePanelContext) -> AnyView

    public init(
        layout: Binding<WorkspaceLayout>,
        context: WorkspacePanelContext,
        panelBuilder: @escaping (WorkspacePanelID, WorkspacePanelContext) -> AnyView = WorkspaceView.defaultPanel
    ) {
        self._layout = layout
        self.context = context
        self.panelBuilder = panelBuilder
    }

    public var body: some View {
        VSplitView {
            HSplitView {
                if layout.isVisible(.fixtureBrowser) || layout.isVisible(.patch) || layout.isVisible(.song) {
                    leadingColumn
                        .frame(minWidth: 180)
                }

                centerColumn
                    .frame(minWidth: 280)

                if layout.isVisible(.inspector) {
                    panelChrome(layout.trailingTabOrInspector) {
                        panelBuilder(.inspector, context)
                    }
                    .frame(minWidth: 180)
                }
            }

            if showsBottom {
                bottomColumn
                    .frame(minHeight: 120)
            }
        }
        .onChange(of: layout) { _, newValue in
            WorkspaceLayoutStore.save(newValue)
        }
    }

    private var showsBottom: Bool {
        layout.isVisible(.universeMonitor) || layout.isVisible(.console) || layout.isVisible(.cueList)
    }

    private var leadingColumn: some View {
        let tabs = leadingTabs
        return VStack(spacing: 0) {
            if tabs.count > 1 {
                Picker("", selection: leadingTabBinding) {
                    ForEach(tabs) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(6)
            }
            panelChrome(resolvedLeadingTab) {
                panelBuilder(resolvedLeadingTab, context)
            }
        }
    }

    private var centerColumn: some View {
        let tabs = centerTabs
        return VStack(spacing: 0) {
            if tabs.count > 1 {
                Picker("", selection: centerTabBinding) {
                    ForEach(tabs) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(6)
            }
            panelChrome(resolvedCenterTab) {
                panelBuilder(resolvedCenterTab, context)
            }
        }
    }

    private var bottomColumn: some View {
        let tabs = bottomTabs
        return VStack(spacing: 0) {
            if tabs.count > 1 {
                Picker("", selection: bottomTabBinding) {
                    ForEach(tabs) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(6)
            }
            panelChrome(resolvedBottomTab) {
                panelBuilder(resolvedBottomTab, context)
            }
        }
    }

    private func panelChrome<Content: View>(_ id: WorkspacePanelID, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(id.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
            Divider()
            content()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var leadingTabs: [WorkspacePanelID] {
        [.fixtureBrowser, .patch, .song].filter { layout.isVisible($0) }
    }

    private var centerTabs: [WorkspacePanelID] {
        [.livePlayback, .patch, .cueList, .programmer].filter { layout.isVisible($0) }
    }

    private var bottomTabs: [WorkspacePanelID] {
        [.universeMonitor, .console, .cueList].filter { layout.isVisible($0) }
    }

    private var resolvedLeadingTab: WorkspacePanelID {
        if leadingTabs.contains(layout.leadingTab) { return layout.leadingTab }
        return leadingTabs.first ?? .fixtureBrowser
    }

    private var resolvedCenterTab: WorkspacePanelID {
        if centerTabs.contains(layout.centerTab) { return layout.centerTab }
        return centerTabs.first ?? .patch
    }

    private var resolvedBottomTab: WorkspacePanelID {
        if bottomTabs.contains(layout.bottomTab) { return layout.bottomTab }
        return bottomTabs.first ?? .universeMonitor
    }

    private var leadingTabBinding: Binding<WorkspacePanelID> {
        Binding(
            get: { resolvedLeadingTab },
            set: { layout.leadingTab = $0 }
        )
    }

    private var centerTabBinding: Binding<WorkspacePanelID> {
        Binding(
            get: { resolvedCenterTab },
            set: { layout.centerTab = $0 }
        )
    }

    private var bottomTabBinding: Binding<WorkspacePanelID> {
        Binding(
            get: { resolvedBottomTab },
            set: { layout.bottomTab = $0 }
        )
    }

    public static func defaultPanel(id: WorkspacePanelID, context: WorkspacePanelContext) -> AnyView {
        AnyView(
            PlaceholderPanel(title: id.title, detail: id.placeholderDetail)
        )
    }
}

private extension WorkspaceLayout {
    var trailingTabOrInspector: WorkspacePanelID { .inspector }
}
