import AuroraOutput
import Foundation

/// Semantic, throttled diagnostics projection (UI-09 A3 / DIAG second-pass).
/// Built by DiagnosticsController — not assembled inside SwiftUI body.
struct DiagnosticsSnapshot: Equatable, Sendable {
    var engineRunning: Bool
    var frameRateHz: Double
    var outputStatusLine: String
    var localDMXStatus: String
    /// Actual runtime enable (not preference).
    var localDMXEnabled: Bool
    var localDMXRequested: Bool
    var localDMXDeviceAvailable: Bool
    var artNetEnabled: Bool
    var sacnEnabled: Bool
    var midiStatus: String
    var midiState: String
    var midiSourceCount: Int
    var remoteStatus: String
    var remoteActuallyRunning: Bool
    var remoteClientCount: Int
    var validationIssueCount: Int
    var driverHealth: [DriverHealthRow]
    var universeRoutes: [UniverseRouteRow]
    var generatedAt: Date

    struct DriverHealthRow: Equatable, Sendable, Identifiable {
        var id: String
        var name: String
        var state: String
        var outputProtocol: String
        var lastError: String?
    }

    struct UniverseRouteRow: Equatable, Sendable, Identifiable {
        var id: UUID
        var number: UInt16
        var name: String
        /// Configured protocol hint.
        var configuredRoute: String
        /// Driver/device availability for this route only.
        var availability: String
        /// Runtime health for this route only.
        var runtimeHealth: String
    }

    /// Equality ignoring `generatedAt` (timer stamp only).
    func semanticallyEqual(to other: DiagnosticsSnapshot) -> Bool {
        engineRunning == other.engineRunning
            && frameRateHz == other.frameRateHz
            && outputStatusLine == other.outputStatusLine
            && localDMXStatus == other.localDMXStatus
            && localDMXEnabled == other.localDMXEnabled
            && localDMXRequested == other.localDMXRequested
            && localDMXDeviceAvailable == other.localDMXDeviceAvailable
            && artNetEnabled == other.artNetEnabled
            && sacnEnabled == other.sacnEnabled
            && midiStatus == other.midiStatus
            && midiState == other.midiState
            && midiSourceCount == other.midiSourceCount
            && remoteStatus == other.remoteStatus
            && remoteActuallyRunning == other.remoteActuallyRunning
            && remoteClientCount == other.remoteClientCount
            && validationIssueCount == other.validationIssueCount
            && driverHealth == other.driverHealth
            && universeRoutes == other.universeRoutes
    }

    static let empty = DiagnosticsSnapshot(
        engineRunning: false,
        frameRateHz: 0,
        outputStatusLine: "",
        localDMXStatus: "",
        localDMXEnabled: false,
        localDMXRequested: false,
        localDMXDeviceAvailable: false,
        artNetEnabled: false,
        sacnEnabled: false,
        midiStatus: "",
        midiState: "off",
        midiSourceCount: 0,
        remoteStatus: "",
        remoteActuallyRunning: false,
        remoteClientCount: 0,
        validationIssueCount: 0,
        driverHealth: [],
        universeRoutes: [],
        generatedAt: .distantPast
    )
}
