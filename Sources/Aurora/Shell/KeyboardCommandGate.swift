import AuroraUI
import Foundation

/// Centralized check: is a text/value editor the key first responder?
/// Used to suppress no-modifier transport shortcuts during editing (UI-02 A2).
@MainActor
enum KeyboardCommandGate {
    /// True when Space/Return/arrows/letter keys should not trigger show transport.
    static var isTextEditingActive: Bool {
        AuroraKeyboardGate.isTextEditingActive
    }
}
