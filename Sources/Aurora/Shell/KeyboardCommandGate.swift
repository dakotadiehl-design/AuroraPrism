import AppKit
import Foundation

/// Centralized check: is a text/value editor the key first responder?
/// Used to suppress no-modifier transport shortcuts during editing (UI-02 A2).
@MainActor
enum KeyboardCommandGate {
    /// True when Space/Return/arrows/letter keys should not trigger show transport.
    static var isTextEditingActive: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView { return true }
        if responder is NSText { return true }
        // Field editor is typically NSTextView; also check class name for SwiftUI bridges.
        let name = NSStringFromClass(type(of: responder))
        if name.contains("TextView") || name.contains("TextField") || name.contains("FieldEditor") {
            return true
        }
        // NSTextField without field editor active still shouldn't steal if it's editing
        if let field = responder as? NSTextField, field.currentEditor() != nil {
            return true
        }
        return false
    }
}
