import AuroraDesignSystem
import AppKit
import AuroraEngine
import AuroraUI
import SwiftUI

struct ShortcutHelpItem: Identifiable, Equatable {
    let id: String
    let keys: String
    let action: String

    init(_ keys: String, _ action: String) {
        self.id = "\(keys)-\(action)"
        self.keys = keys
        self.action = action
    }
}

enum ShortcutHelpContext: Equatable {
    case stage, programmer, fixtures, groups, cueBlocks, palettes, cues, song, inspector, diagnostics

    var title: String {
        switch self {
        case .stage: return "Stage"
        case .programmer: return "Programmer"
        case .fixtures: return "Fixtures"
        case .groups: return "Groups"
        case .cueBlocks: return "Cue Blocks"
        case .palettes: return "Palettes"
        case .cues: return "Cue List"
        case .song: return "Song"
        case .inspector: return "Inspector"
        case .diagnostics: return "Diagnostics"
        }
    }

    var items: [ShortcutHelpItem] {
        switch self {
        case .stage:
            return [.init("Click + drag", "Marquee select"), .init("Space + drag", "Pan stage"), .init("⌘ + scroll", "Zoom at pointer"), .init("⌘⇧ + / −", "Zoom in or out"), .init("⌘R", "Rotate selection 90°"), .init("⇧R", "Enter exact rotation"), .init("Esc", "Cancel or clear selection")]
        case .programmer:
            return [.init("⇧D  number  ↩", "Set selected dimmer"), .init("Esc", "Cancel numeric entry"), .init("?", "Pin shortcut help")]
        case .cues:
            return [.init("Space", "Go / start"), .init("↑  ↓", "Select cues"), .init("⌘ +", "New cue"), .init("↩", "Rename"), .init("Esc", "Cancel editing")]
        case .fixtures, .groups:
            return [.init("⌘ click", "Toggle selection"), .init("⇧ click", "Extend selection"), .init("Esc", "Clear selection"), .init("?", "Pin shortcut help")]
        case .cueBlocks:
            return [.init("⌘⇧B", "New cue block"), .init("⌘⇧G", "New cue block group"), .init("Click", "Activate cue block"), .init("⌘ click", "Combine selections"), .init("Esc", "Cancel editing"), .init("?", "Pin shortcut help")]
        case .palettes:
            return [.init("Click", "Apply palette"), .init("⌘ click", "Extend selection"), .init("Esc", "Cancel editing"), .init("?", "Pin shortcut help")]
        case .song:
            return [.init("↑  ↓", "Select song entry"), .init("↩", "Load selection"), .init("Esc", "Cancel editing"), .init("?", "Pin shortcut help")]
        case .inspector:
            return [.init("↩", "Commit field edit"), .init("Esc", "Cancel field edit"), .init("?", "Pin shortcut help")]
        case .diagnostics:
            return [.init("⌘C", "Copy selected details"), .init("?", "Pin shortcut help")]
        }
    }
}

private struct ShortcutHelpHUDModifier: ViewModifier {
    let context: ShortcutHelpContext
    let items: [ShortcutHelpItem]?
    @State private var peeking = false
    @State private var pinned = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if peeking || pinned {
                    card
                        .padding(14)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottomTrailing)))
                }
            }
            .background(
                ShortcutHelpKeyMonitor(
                    isActive: { !AuroraKeyboardGate.isTextEditingActive },
                    isPinned: { pinned },
                    onQuestionDown: { peeking = true },
                    onQuestionUp: { wasTap in
                        if wasTap { pinned.toggle() }
                        peeking = false
                    },
                    onEscape: {
                        pinned = false
                        peeking = false
                    }
                )
                .allowsHitTesting(false)
            )
            .animation(.easeOut(duration: 0.14), value: peeking || pinned)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Shortcuts — \(context.title)")
                    .font(AuroraTypography.sectionHeading)
                    .foregroundStyle(AuroraColor.textPrimary)
                Spacer(minLength: 18)
                if pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(AuroraColor.accentBright)
                }
            }
            ForEach(items ?? context.items) { item in
                HStack(spacing: 12) {
                    Text(item.keys)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AuroraColor.textPrimary)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 86, minHeight: 27)
                        .background(Color.white.opacity(0.09))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    Text(item.action)
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textSecondary)
                    Spacer(minLength: 0)
                }
            }
            Text(pinned ? "Tap ? or press Escape to close" : "Release to hide · tap ? to pin")
                .font(.system(size: 10))
                .foregroundStyle(AuroraColor.textTertiary)
        }
        .padding(14)
        .frame(width: 310)
        .background(.ultraThinMaterial)
        .background(AuroraColor.surfacePanel.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AuroraColor.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.38), radius: 18, y: 8)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(context.title) keyboard shortcuts")
    }
}

extension View {
    func shortcutHelpHUD(_ context: ShortcutHelpContext, items: [ShortcutHelpItem]? = nil) -> some View {
        modifier(ShortcutHelpHUDModifier(context: context, items: items))
    }
}

extension AppModel {
    /// Only advertises numeric Programmer shortcuts that can affect at least one selected fixture.
    var programmerShortcutHelpItems: [ShortcutHelpItem] {
        let fixtureIDs = session.selection.snapshot.orderedFixtureIDs
        let effective = FixtureCapabilityMap.build(from: session.project, fixtureIDs: fixtureIDs)
        let physical = ProgrammerAttributePresentationResolver.physicalCapabilityMap(
            orderedFixtureIDs: fixtureIDs,
            project: session.project
        )
        let fogNames: Set<String> = ["fogoutput", "hazeoutput", "smokeoutput", "fog", "haze", "smoke"]
        let fanNames: Set<String> = ["fanspeed", "fan_speed", "blowerspeed", "fan", "blower"]

        var items: [ShortcutHelpItem] = []
        if fixtureIDs.contains(where: { effective[$0]?.contains("intensity") == true }) {
            items.append(.init("⇧D  number  ↩", "Set selected dimmer"))
        }
        if fixtureIDs.contains(where: { id in
            !Set((physical[id] ?? []).map { $0.lowercased() }).intersection(fogNames).isEmpty
        }) {
            items.append(.init("⇧F  number  ↩", "Set fog or haze output"))
        }
        if fixtureIDs.contains(where: { id in
            !Set((physical[id] ?? []).map { $0.lowercased() }).intersection(fanNames).isEmpty
        }) {
            items.append(.init("⇧S  number  ↩", "Set fan speed"))
        }
        if !items.isEmpty {
            items.append(.init("Esc", "Cancel numeric entry"))
        }
        items.append(.init("?", "Pin shortcut help"))
        return items
    }
}

private struct ShortcutHelpKeyMonitor: NSViewRepresentable {
    var isActive: () -> Bool
    var isPinned: () -> Bool
    var onQuestionDown: () -> Void
    var onQuestionUp: (Bool) -> Void
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.view = nsView
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.uninstall() }

    @MainActor final class Coordinator {
        var parent: ShortcutHelpKeyMonitor
        weak var view: NSView?
        private var monitor: Any?
        private var questionDownAt: TimeInterval?
        init(parent: ShortcutHelpKeyMonitor) { self.parent = parent }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }
        func uninstall() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard event.window === view?.window else { return event }
            if event.type == .keyDown, event.keyCode == 53, parent.isPinned() {
                parent.onEscape(); return nil
            }
            let isQuestion = event.keyCode == 44 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)
            guard isQuestion else { return event }
            if event.type == .keyDown {
                guard parent.isActive(), pointerIsInsideSurface() else { return event }
                if !event.isARepeat, questionDownAt == nil {
                    questionDownAt = event.timestamp
                    parent.onQuestionDown()
                }
                return nil
            }
            guard questionDownAt != nil else { return event }
            let wasTap = event.timestamp - (questionDownAt ?? event.timestamp) < 0.32
            questionDownAt = nil
            parent.onQuestionUp(wasTap)
            return nil
        }

        /// Query pointer geometry without publishing hover state. Native menus live
        /// in separate windows; rebuilding their source view while AppKit is tracking
        /// a menu can invalidate the pending menu action.
        private func pointerIsInsideSurface() -> Bool {
            guard let view, let window = view.window else { return false }
            let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            let localPoint = view.convert(windowPoint, from: nil)
            return view.bounds.contains(localPoint)
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
