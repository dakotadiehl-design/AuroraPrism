import AppKit
import AuroraModel
import AuroraOutput
import Foundation

/// Drivers, routes, network output configuration and health line (Stage C + HW-01 Local DMX).
@MainActor
final class OutputController: ObservableObject {
    let outputManager = OutputManager()
    private let nullDriver = NullOutputDriver(name: "Null")
    private let artNetDriver: ArtNetOutputDriver
    private let sacnDriver: SACNOutputDriver
    private var localDMXDriver: ENTTECUSBDMXProDriver?
    private var localDMXTransport: ENTTECSerialTransport?
    private let localDMXDiscoverer: LocalDMXDeviceDiscovering

    @Published var artNetConfig: ArtNetConfig
    @Published var sacnConfig: SACNConfig
    @Published private(set) var outputStatus: String = "Output: Null"
    @Published private(set) var availableLocalDMXDevices: [LocalDMXDeviceDescriptor] = []
    @Published var selectedLocalDMXDeviceID: String?
    @Published var localDMXEnabled: Bool = false
    @Published private(set) var localDMXStatus: String = "Local DMX: off"

    init(localDMXDiscoverer: LocalDMXDeviceDiscovering = MacLocalDMXDeviceEnumerator()) {
        self.localDMXDiscoverer = localDMXDiscoverer
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
        rescanLocalDMXDevices()
        refreshOutputStatus()
    }

    func stopAll() {
        artNetDriver.stop()
        sacnDriver.stop()
        disableLocalDMX()
        outputManager.stopAll()
    }

    // MARK: - Local DMX (ENTTEC USB Pro framing — not Open DMX)

    func rescanLocalDMXDevices() {
        availableLocalDMXDevices = localDMXDiscoverer.enumerate()
        if let selectedLocalDMXDeviceID,
           !availableLocalDMXDevices.contains(where: { $0.id == selectedLocalDMXDeviceID }) {
            // Keep selection ID for reconnect; status reflects missing.
            localDMXStatus = "Local DMX: selected device not present"
        }
    }

    func setLocalDMXEnabled(_ enabled: Bool, engineRunning: Bool, log: (String) -> Void) {
        if enabled {
            enableLocalDMX(engineRunning: engineRunning, log: log)
        } else {
            disableLocalDMX()
            log("Local DMX disabled")
        }
        refreshOutputStatus()
    }

    /// HW-02: driver owns transport open/close. Controller does not pre-open.
    private func enableLocalDMX(engineRunning: Bool, log: (String) -> Void) {
        rescanLocalDMXDevices()
        guard let id = selectedLocalDMXDeviceID,
              let device = availableLocalDMXDevices.first(where: { $0.id == id }),
              let path = device.serialPath
        else {
            localDMXEnabled = false
            localDMXStatus = "Local DMX: no device selected"
            log(localDMXStatus)
            return
        }
        disableLocalDMX()
        let transport = MacENTTECSerialTransport(path: path)
        let driver = ENTTECUSBDMXProDriver(name: device.displayName, transport: transport)
        outputManager.register(driver)
        do {
            if engineRunning {
                try driver.start()
                localDMXStatus = "Local DMX: \(device.displayName) · running"
            } else {
                // Registered; will start when engine runs.
                localDMXStatus = "Local DMX: \(device.displayName) · waiting for engine"
            }
            localDMXTransport = transport
            localDMXDriver = driver
            localDMXEnabled = true
            log(localDMXStatus)
        } catch {
            outputManager.unregister(id: driver.id)
            driver.stop()
            transport.close()
            localDMXTransport = nil
            localDMXDriver = nil
            localDMXEnabled = false
            localDMXStatus = "Local DMX: open/start failed — \(error.localizedDescription)"
            log(localDMXStatus)
        }
    }

    private func disableLocalDMX() {
        if let driver = localDMXDriver {
            driver.stop()
            outputManager.unregister(id: driver.id)
        }
        // stop() closes transport via driver; ensure handle release.
        localDMXTransport?.close()
        localDMXTransport = nil
        localDMXDriver = nil
        localDMXEnabled = false
        localDMXStatus = "Local DMX: off"
    }

    /// Start local driver if enabled and registered but not running (engine just started).
    func startLocalDMXIfNeeded() {
        guard localDMXEnabled, let driver = localDMXDriver, !driver.isRunning else { return }
        do {
            try driver.start()
            localDMXStatus = "Local DMX: running"
            refreshOutputStatus()
        } catch {
            localDMXEnabled = false
            localDMXStatus = "Local DMX: start failed — \(error.localizedDescription)"
            outputManager.unregister(id: driver.id)
            driver.stop()
            localDMXTransport?.close()
            localDMXTransport = nil
            localDMXDriver = nil
            refreshOutputStatus()
        }
    }

    func setArtNetEnabled(_ enabled: Bool, engineRunning: Bool, log: (String) -> Void) {
        artNetConfig.enabled = enabled
        artNetConfig.save()
        applyArtNetRegistration(engineRunning: engineRunning)
        refreshOutputStatus()
        log(enabled ? "Art-Net enabled → \(artNetConfig.destinationHost)" : "Art-Net disabled")
    }

    func setArtNetDestination(_ host: String, engineRunning: Bool) {
        artNetConfig.destinationHost = host
        artNetConfig.useBroadcast = host.contains("255")
        artNetConfig.save()
        artNetDriver.applyConfig(artNetConfig)
        refreshOutputStatus()
    }

    func setSACNEnabled(_ enabled: Bool, engineRunning: Bool, log: (String) -> Void) {
        sacnConfig.enabled = enabled
        sacnConfig.save()
        applySACNRegistration(engineRunning: engineRunning)
        refreshOutputStatus()
        log(enabled ? "sACN enabled" : "sACN disabled")
    }

    func setSACNUnicastHost(_ host: String?) {
        let trimmed = host?.trimmingCharacters(in: .whitespacesAndNewlines)
        sacnConfig.destinationHost = (trimmed?.isEmpty == false) ? trimmed : nil
        sacnConfig.save()
        sacnDriver.applyConfig(sacnConfig)
        refreshOutputStatus()
    }

    func healthSnapshots() -> [OutputHealthSnapshot] {
        outputManager.healthSnapshots()
    }

    /// Pure live presentation from driver health (CR-12).
    /// Does **not** mutate `@Published` state — safe to call from SwiftUI body.
    func presentationSnapshot() -> OutputPresentationSnapshot {
        var health = healthSnapshots()
        if artNetConfig.enabled,
           !health.contains(where: { $0.driverID == artNetDriver.id }) {
            health.append(artNetDriver.healthSnapshot())
        }
        if sacnConfig.enabled,
           !health.contains(where: { $0.driverID == sacnDriver.id }) {
            health.append(sacnDriver.healthSnapshot())
        }
        if let local = localDMXDriver,
           !health.contains(where: { $0.driverID == local.id }) {
            health.append(local.healthSnapshot())
        }
        return OutputPresentationSnapshot.from(health: health)
    }

    /// Mutating refresh for timers / enable-disable (CR-12).
    func refreshOutputStatus() {
        let snap = presentationSnapshot()
        if outputStatus != snap.statusLine {
            outputStatus = snap.statusLine
        }
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
}
