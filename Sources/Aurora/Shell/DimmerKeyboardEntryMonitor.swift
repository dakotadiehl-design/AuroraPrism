import AppKit
import SwiftUI

enum ProgrammerNumericShortcutTarget {
    case dimmer
    case fog
    case fan
}

/// Silent numeric entry for selected fixtures' Programmer controls.
/// Shift-D/F/S arms entry; digits are committed only when Return is pressed.
struct DimmerKeyboardEntryMonitor: NSViewRepresentable {
    var isEnabled: () -> Bool
    var onCommitPercent: (ProgrammerNumericShortcutTarget, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onCommitPercent: onCommitPercent)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onCommitPercent = onCommitPercent
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        var isEnabled: () -> Bool
        var onCommitPercent: (ProgrammerNumericShortcutTarget, Int) -> Void
        private var monitor: Any?
        private var digits = ""
        private var target: ProgrammerNumericShortcutTarget?

        init(
            isEnabled: @escaping () -> Bool,
            onCommitPercent: @escaping (ProgrammerNumericShortcutTarget, Int) -> Void
        ) {
            self.isEnabled = isEnabled
            self.onCommitPercent = onCommitPercent
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            cancel()
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if digits.isEmpty {
                guard flags == [.shift], isEnabled() else { return event }
                switch key {
                case "d": target = .dimmer
                case "f": target = .fog
                case "s": target = .fan
                default: return event
                }
                digits = "_" // armed sentinel; no value has been entered yet
                return nil
            }

            if key == "\u{1b}" { // Escape
                cancel()
                return nil
            }
            if event.keyCode == 51 { // Delete/backspace
                if digits == "_" || digits.count == 1 {
                    digits = "_"
                } else {
                    digits.removeLast()
                }
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 { // Return / keypad Enter
                commit()
                return nil
            }
            if key.count == 1, let character = key.first, character.isNumber {
                if digits == "_" { digits = "" }
                if digits.count < 3 { digits.append(character) }
                return nil
            }

            // An unrelated command abandons entry and continues normally.
            cancel()
            return event
        }

        private func commit() {
            guard digits != "_", let percent = Int(digits), let target else {
                digits = ""
                self.target = nil
                return
            }
            digits = ""
            self.target = nil
            onCommitPercent(target, min(100, max(0, percent)))
        }

        private func cancel() {
            digits = ""
            target = nil
        }
    }
}
