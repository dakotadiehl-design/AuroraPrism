import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Shared first-responder check so Delete/Backspace never unpatch while editing text.
@MainActor
public enum AuroraKeyboardGate {
    public static var isTextEditingActive: Bool {
        #if canImport(AppKit)
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView { return true }
        if responder is NSText { return true }
        let name = NSStringFromClass(type(of: responder))
        if name.contains("TextView") || name.contains("TextField") || name.contains("FieldEditor") {
            return true
        }
        if let field = responder as? NSTextField, field.currentEditor() != nil {
            return true
        }
        return false
        #else
        return false
        #endif
    }
}
