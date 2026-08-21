import AppKit
import AuroraDiagnostics
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
    /// Currently matched device runtime id (path/id), not a silent substitute.
    @Published var selectedLocalDMXDeviceID: String?
    /// Actual driver enabled state — never true when device missing (A1).
    @Published private(set) var localDMXEnabled: Bool = false
    @Published private(set) var localDMXStatus: String = "Local DMX: off"
    /// Operator requested enable; may be true while actualEnabled is false if device absent.
    @Published private(set) var localDMXRequestedEnabled: Bool = false
    /// Whether saved hardware identity is present among enumerated devices.
    @Published private(set) var localDMXConfiguredDeviceAvailable: Bool = false

    private var prefs: AppSettingsStore?

    init(
        localDMXDiscoverer: LocalDMXDeviceDiscovering = MacLocalDMXDeviceEnumerator(),
        settings: AppSettingsStore? = nil
    ) {
        self.localDMXDiscoverer = localDMXDiscoverer
        self.prefs = settings
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

    func attachSettings(_ settings: AppSettingsStore) {
        prefs = settings
        localDMXRequestedEnabled = settings.localDMX.requestedEnabled
        rescanLocalDMXDevices()
        // Auto-enable only when configured device is present (A1).
        if settings.localDMX.requestedEnabled, localDMXConfiguredDeviceAvailable {
            // Caller should pass engineRunning after AppModel ready.
        }
    }

    func stopAll() {
        // Local DMX first: blackout + serial close must finish before process exit.
        disableLocalDMX()
        artNetDriver.stop()
        sacnDriver.stop()
        outputManager.stopAll()
    }

    // MARK: - Local DMX (ENTTEC USB Pro framing — not Open DMX)

    /// UI-08 A1: match by hardware identity first; never silently select another device.
    func rescanLocalDMXDevices() {
        availableLocalDMXDevices = localDMXDiscoverer.enumerate()
        let pref = prefs?.localDMX ?? .empty
        localDMXRequestedEnabled = pref.requestedEnabled

        if let match = resolveConfiguredDevice(pref: pref, devices: availableLocalDMXDevices) {
            selectedLocalDMXDeviceID = match.id
            localDMXConfiguredDeviceAvailable = true
            if localDMXEnabled {
                localDMXStatus = "Local DMX: \(match.displayName)"
            } else if pref.requestedEnabled {
                localDMXStatus = "Local DMX: device available — enable to start"
            } else {
                localDMXStatus = "Local DMX: \(match.displayName) selected"
            }
        } else {
            localDMXConfiguredDeviceAvailable = false
            // Do not clear preference identity; do not pick a substitute device.
            selectedLocalDMXDeviceID = nil
            if pref.hardwareIdentifier != nil || pref.lastEndpointPath != nil {
                if pref.requestedEnabled {
                    localDMXStatus = "Local DMX: configured device unavailable"
                } else {
                    localDMXStatus = "Local DMX: configured device not present"
                }
            } else if availableLocalDMXDevices.isEmpty {
                localDMXStatus = "Local DMX: no devices"
            } else {
                localDMXStatus = "Local DMX: no device selected"
            }
            if localDMXEnabled {
                // Device disappeared under us.
                disableLocalDMX(persistRequested: pref.requestedEnabled)
            }
        }
    }

    private func resolveConfiguredDevice(
        pref: LocalDMXPersistedPreference,
        devices: [LocalDMXDeviceDescriptor]
    ) -> LocalDMXDeviceDescriptor? {
        if let hw = pref.hardwareIdentifier, !hw.isEmpty {
            if let byHW = devices.first(where: { ($0.hardwareIdentifier ?? $0.id) == hw }) {
                return byHW
            }
            // Hardware identity set but not found — do not fall through to another device.
            return nil
        }
        // Low-confidence path fallback only when no hardware identity was ever saved.
        if let path = pref.lastEndpointPath, !path.isEmpty {
            return devices.first(where: { $0.serialPath == path || $0.id == path })
        }
        return nil
    }

    func selectLocalDMXDevice(id: String?, engineRunning: Bool) {
        if id == nil || id?.isEmpty == true {
            selectedLocalDMXDeviceID = nil
            persistLocalDMXSelection(device: nil, requestedEnabled: false)
            disableLocalDMX(persistRequested: false)
            localDMXStatus = "Local DMX: no device selected"
            refreshOutputStatus()
            return
        }
        guard let device = availableLocalDMXDevices.first(where: { $0.id == id }) else {
            localDMXStatus = "Local DMX: selection not in scan list"
            return
        }
        selectedLocalDMXDeviceID = device.id
        localDMXConfiguredDeviceAvailable = true
        persistLocalDMXSelection(device: device, requestedEnabled: localDMXRequestedEnabled)
        localDMXStatus = "Local DMX: \(device.displayName) selected"
        if localDMXRequestedEnabled {
            enableLocalDMX(engineRunning: engineRunning)
        }
        refreshOutputStatus()
    }

    func setLocalDMXEnabled(_ enabled: Bool, engineRunning: Bool) {
        localDMXRequestedEnabled = enabled
        if enabled {
            enableLocalDMX(engineRunning: engineRunning)
        } else {
            disableLocalDMX(persistRequested: false)
        }
        // Persist requested flag + current device identity if any.
        let device = availableLocalDMXDevices.first(where: { $0.id == selectedLocalDMXDeviceID })
        persistLocalDMXSelection(device: device, requestedEnabled: enabled)
        refreshOutputStatus()
    }

    private func persistLocalDMXSelection(device: LocalDMXDeviceDescriptor?, requestedEnabled: Bool) {
        guard let prefs else { return }
        var pref = prefs.localDMX
        pref.requestedEnabled = requestedEnabled
        if let device {
            pref.hardwareIdentifier = device.hardwareIdentifier ?? device.id
            pref.lastEndpointPath = device.serialPath ?? device.id
        }
        prefs.updateLocalDMX(pref)
    }

    /// HW-02: driver owns transport open/close. Controller does not pre-open.
    private func enableLocalDMX(engineRunning: Bool) {
        rescanLocalDMXDevices()
        guard localDMXConfiguredDeviceAvailable,
              let id = selectedLocalDMXDeviceID,
              let device = availableLocalDMXDevices.first(where: { $0.id == id }),
              let path = device.serialPath
        else {
            localDMXEnabled = false
            localDMXStatus = localDMXRequestedEnabled
                ? "Local DMX: configured device unavailable"
                : "Local DMX: no device selected"
            return
        }
        disableLocalDMX(persistRequested: localDMXRequestedEnabled)
        let transport = MacENTTECSerialTransport(path: path)
        let driver = ENTTECUSBDMXProDriver(name: device.displayName, transport: transport)
        outputManager.register(driver)
        do {
            if engineRunning {
                try driver.start()
                localDMXStatus = "Local DMX: \(device.displayName) · running"
            } else {
                localDMXStatus = "Local DMX: \(device.displayName) · waiting for engine"
            }
            localDMXTransport = transport
            localDMXDriver = driver
            localDMXEnabled = true
            persistLocalDMXSelection(device: device, requestedEnabled: true)
        } catch {
            outputManager.unregister(id: driver.id)
            driver.stop()
            transport.close()
            localDMXTransport = nil
            localDMXDriver = nil
            localDMXEnabled = false
            localDMXStatus = "Local DMX: open/start failed — \(PrismErrorReporting.userFacingMessage(for: error))"
        }
    }

    private func disableLocalDMX(persistRequested: Bool = false) {
        // Unregister first so the engine cannot enqueue more DMX frames to this driver.
        let driver = localDMXDriver
        let transport = localDMXTransport
        if let driver {
            outputManager.unregister(id: driver.id)
        }
        localDMXDriver = nil
        localDMXTransport = nil
        localDMXEnabled = false
        if !persistRequested {
            localDMXStatus = "Local DMX: off"
        }
        // Synchronous stop: sends a zero DMX frame then closes the serial session.
        // Must not be deferred to a background queue — process exit would race past close
        // and the ENTTEC Pro would keep retransmitting the last levels (green LED).
        // Transport I/O is non-blocking with timeouts, so this is quit-safe.
        driver?.stop()
        transport?.close()
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
            localDMXStatus = "Local DMX: start failed — \(PrismErrorReporting.userFacingMessage(for: error))"
            outputManager.unregister(id: driver.id)
            driver.stop()
            localDMXTransport?.close()
            localDMXTransport = nil
            localDMXDriver = nil
            refreshOutputStatus()
        }
    }

    func setArtNetEnabled(_ enabled: Bool, engineRunning: Bool) {
        artNetConfig.enabled = enabled
        artNetConfig.save()
        applyArtNetRegistration(engineRunning: engineRunning)
        refreshOutputStatus()
    }

    func setArtNetDestination(_ host: String, engineRunning: Bool) {
        artNetConfig.destinationHost = host
        artNetConfig.useBroadcast = host.contains("255")
        artNetConfig.save()
        artNetDriver.applyConfig(artNetConfig)
        refreshOutputStatus()
    }

    func setSACNEnabled(_ enabled: Bool, engineRunning: Bool) {
        sacnConfig.enabled = enabled
        sacnConfig.save()
        applySACNRegistration(engineRunning: engineRunning)
        refreshOutputStatus()
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
