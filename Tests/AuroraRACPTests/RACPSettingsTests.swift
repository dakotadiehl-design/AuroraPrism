import Foundation
import AuroraModel
import AuroraUI
import XCTest
@testable import Aurora

@MainActor
final class RACPSettingsTests: XCTestCase {
    func testStageGlyphStyleDefaultsAndRoundTripsWithoutProjectState() throws {
        let suite = "PrismGlyphSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let project = ShowProject.empty(name: "Unchanged")
        let projectBefore = project
        let initial = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(initial.stageGlyphStyle, .legacyV1)
        initial.stageGlyphStyle = .prismV3
        initial.save()

        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.stageGlyphStyle, .prismV3)
        XCTAssertEqual(project, projectBefore)
    }

    func testInvalidStageGlyphStyleFallsBackToLegacy() throws {
        let suite = "PrismGlyphSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("futureRenderer", forKey: "prism.stage.glyphStyle.v1")

        XCTAssertEqual(AppSettingsStore(defaults: defaults).stageGlyphStyle, .legacyV1)
    }

    func testRemoteControlPreferenceDefaultsDisabledAndRoundTrips() throws {
        let suite = "PrismRACPSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let initial = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(initial.racpRemoteControl.enabled)
        XCTAssertEqual(initial.racpRemoteControl.port, 9_000)
        let generatedPeerID = initial.racpRemoteControl.peerID

        // Initialization persists the generated identity before rACP is ever
        // enabled, so repeated launches share one authoritative identity.
        let repeated = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(repeated.racpRemoteControl.peerID, generatedPeerID)

        let saved = RACPRemoteControlPreference(
            enabled: true,
            port: 12_345,
            peerID: "main-stage"
        )
        initial.updateRACPRemoteControl(saved)

        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.racpRemoteControl, saved)
    }

    func testInvalidPersistedRemoteControlPreferenceFallsBackSafely() throws {
        let suite = "PrismRACPSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let invalid = RACPRemoteControlPreference(enabled: true, port: 0, peerID: "bad id")
        defaults.set(
            try JSONEncoder().encode(invalid),
            forKey: "prism.remote.racp.v1"
        )

        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(restored.racpRemoteControl.enabled)
        XCTAssertEqual(restored.racpRemoteControl.port, 9_000)
    }
}
