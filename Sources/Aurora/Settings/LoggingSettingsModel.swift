import AuroraDiagnostics
import AppKit
import Combine
import Foundation

@MainActor
final class LoggingSettingsModel: ObservableObject {
    @Published var configuration: PrismLogConfiguration
    @Published var confirmReset = false
    @Published var copiedMessage: String?

    private let apply: (PrismLogConfiguration) -> Void

    init(configuration: PrismLogConfiguration, apply: @escaping (PrismLogConfiguration) -> Void) {
        self.configuration = configuration
        self.apply = apply
    }

    var profile: PrismLogProfile {
        get { configuration.profile }
        set { applyProfile(newValue) }
    }

    func applyProfile(_ profile: PrismLogProfile) {
        switch profile {
        case .productionDefaults: replace(.productionDefaults)
        case .troubleshooting: replace(.troubleshooting)
        case .verboseAll: replace(.verboseAll)
        case .custom:
            var kept = configuration
            kept.profile = .custom
            replace(kept)
        }
    }

    func setLevel(_ level: PrismLogLevel, for category: PrismLogCategory) {
        replace(configuration.setting(category, to: level))
    }

    func setGroup(_ group: PrismLogCategoryGroup, to level: PrismLogLevel) {
        replace(configuration.setting(group: group, to: level))
    }

    func setAll(to level: PrismLogLevel) {
        replace(configuration.settingAll(to: level))
    }

    func resetDefaults() {
        replace(.productionDefaults)
    }

    var supportCommand: String {
        "log show --predicate 'subsystem == \"\(UnifiedPrismLogger.subsystem)\"' --last 15m"
    }

    var streamCommand: String {
        "log stream --predicate 'subsystem == \"\(UnifiedPrismLogger.subsystem)\"'"
    }

    func copySupportCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(supportCommand, forType: .string)
        copiedMessage = "Copied the support log command."
    }

    func copyStreamCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(streamCommand, forType: .string)
        copiedMessage = "Copied the live log command."
    }

    private func replace(_ config: PrismLogConfiguration) {
        configuration = config
        apply(config)
    }
}
