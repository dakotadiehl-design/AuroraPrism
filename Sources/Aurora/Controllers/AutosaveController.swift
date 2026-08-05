import AuroraModel
import Foundation

/// Periodic autosave of the open document package (P3-3 / UI-GATE-7).
///
/// The callback is expected to schedule package I/O off MainActor and only mark
/// the document saved when the captured state ID still matches.
@MainActor
final class AutosaveController {
    private var timer: Timer?
    var interval: TimeInterval = 120
    var isEnabled: Bool = true

    /// Called when an autosave should begin (may schedule background work).
    var onAutosave: (() -> Void)?

    func start() {
        stop()
        guard isEnabled, interval >= 30 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isEnabled else { return }
                self.onAutosave?()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
