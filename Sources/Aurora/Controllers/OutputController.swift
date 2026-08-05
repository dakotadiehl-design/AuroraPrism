import AppKit
import AuroraModel
import AuroraOutput
import Foundation

/// Drivers, routes, network output configuration and health line (Stage C).
@MainActor
final class OutputController: ObservableObject {
    let outputManager = OutputManager()
    private let nullDriver = NullOutputDriver(name: "Null")
    private let artNetDriver: ArtNetOutputDriver
    private let sacnDriver: SACNOutputDriver

    @Published var artNetConfig: ArtNetConfig
    @Published var sacnConfig: SACNConfig
    @Published private(set) var outputStatus: String = "Output: Null"

    init() {
        let artConfig = ArtNetConfig.load()
        self.artNetConfig = artConfig
        self.artNetDriver = ArtNetOutputDriver(config: artConfig)
        let sacn = SACNConfig.load()
        self.sacnConfig = sacn
        self.sacnDriver = SACNOutputDriver(config: sacn)
        outputManager.register(nullDriver)
        if artConfig.enabled {
            outputManager.register(artNetDriver)
        }
        if sacn.enabled {
            outputManager.register(sacnDriver)
        }
        refreshOutputStatus()
    }

    func stopAll() {
        artNetDriver.stop()
        sacnDriver.stop()
        outputManager.stopAll()
    }

    func setArtNetEnabled(_ enabled: Bool, engineRunning: Bool, log: (String) -> Void) {
        artNetConfig.enabled = enabled
        artNetConfig.save()
        applyArtNetRegistration(engineRunning: engineRunning)
        refreshOutputStatus()
        log(enabled ? "Art-Net enabled → \(artNetConfig.destinationHost)" : "Art-Net disabled")
        objectWillChange.send()
    }

    func setArtNetDestination(_ host: String, engineRunning: Bool) {
        artNetConfig.destinationHost = host
        artNetConfig.useBroadcast = host.contains("255")
        artNetConfig.save()
        artNetDriver.applyConfig(artNetConfig)
        refreshOutputStatus()
        objectWillChange.send()
    }

    func setSACNEnabled(_ enabled: Bool, engineRunning: Bool, log: (String) -> Void) {
        sacnConfig.enabled = enabled
        sacnConfig.save()
        applySACNRegistration(engineRunning: engineRunning)
        refreshOutputStatus()
        log(enabled ? "sACN enabled" : "sACN disabled")
        objectWillChange.send()
    }

    func setSACNUnicastHost(_ host: String?) {
        let trimmed = host?.trimmingCharacters(in: .whitespacesAndNewlines)
        sacnConfig.destinationHost = (trimmed?.isEmpty == false) ? trimmed : nil
        sacnConfig.save()
        sacnDriver.applyConfig(sacnConfig)
        refreshOutputStatus()
        objectWillChange.send()
    }

    func healthSnapshots() -> [OutputHealthSnapshot] {
        outputManager.healthSnapshots()
    }

    func promptArtNetDestination(engineRunning: Bool, enableIfNeeded: (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Art-Net Destination"
        alert.informativeText = "Host IP (unicast) or 255.255.255.255 (broadcast). Show universe N → Art-Net N\(artNetConfig.universeOffset)."
        let field = NSTextField(string: artNetConfig.destinationHost)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            setArtNetDestination(field.stringValue, engineRunning: engineRunning)
            if !artNetConfig.enabled {
                enableIfNeeded(true)
            }
        }
    }

    func promptSACNDestination(enableIfNeeded: (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "sACN Destination"
        alert.informativeText = "Leave empty for per-universe multicast (239.255.x.y). Or set a unicast node IP. Show U N → sACN N+\(sacnConfig.universeOffset)."
        let field = NSTextField(string: sacnConfig.destinationHost ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        field.placeholderString = "multicast"
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            setSACNUnicastHost(field.stringValue)
            if !sacnConfig.enabled {
                enableIfNeeded(true)
            }
        }
    }

    private func applyArtNetRegistration(engineRunning: Bool) {
        if artNetConfig.enabled {
            artNetDriver.applyConfig(artNetConfig)
            outputManager.register(artNetDriver)
            if engineRunning {
                do {
                    try artNetDriver.start()
                } catch {
                    // Health snapshot carries the error.
                }
            }
        } else {
            artNetDriver.stop()
            outputManager.unregister(id: artNetDriver.id)
        }
    }

    private func applySACNRegistration(engineRunning: Bool) {
        if sacnConfig.enabled {
            sacnDriver.applyConfig(sacnConfig)
            outputManager.register(sacnDriver)
            if engineRunning {
                do {
                    try sacnDriver.start()
                } catch {
                }
            }
        } else {
            sacnDriver.stop()
            outputManager.unregister(id: sacnDriver.id)
        }
    }

    func refreshOutputStatus() {
        let health = healthSnapshots()
        var parts: [String] = []
        for h in health where h.outputProtocol == .artNet || h.outputProtocol == .sACN {
            if h.state == .disabled { continue }
            let err = h.lastError.map { " err:\($0)" } ?? ""
            parts.append("\(h.name) \(h.state.rawValue)\(err)")
        }
        if artNetConfig.enabled {
            let err = artNetDriver.lastError.map { " err:\($0)" } ?? ""
            if !parts.contains(where: { $0.contains("Art") }) {
                parts.append("Art-Net \(artNetConfig.destinationHost):\(artNetConfig.destinationPort)\(err)")
            }
        }
        if sacnConfig.enabled {
            let dest = sacnConfig.destinationHost ?? "multicast"
            let err = sacnDriver.lastError.map { " err:\($0)" } ?? ""
            if !parts.contains(where: { $0.contains("sACN") || $0.contains("sACN") }) {
                parts.append("sACN \(dest):\(sacnConfig.destinationPort)\(err)")
            }
        }
        outputStatus = parts.isEmpty ? "Output: Null only" : parts.joined(separator: " · ")
    }
}
