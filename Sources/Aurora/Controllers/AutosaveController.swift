import AuroraModel
import Foundation

/// Periodic autosave of the open document package (P3-3).
@MainActor
final class AutosaveController {
    private var timer: Timer?
    var interval: TimeInterval = 120
    var isEnabled: Bool = true

    /// Called to perform save; return true if saved.
    var onAutosave: (() -> Bool)?

    func start() {
        stop()
        guard isEnabled, interval >= 30 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isEnabled else { return }
                _ = self.onAutosave?()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
