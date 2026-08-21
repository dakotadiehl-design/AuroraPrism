import AuroraDiagnostics
import AuroraEngine
import AuroraModel
import AuroraMusical
import AuroraOutput
import XCTest

final class LoggingSettingsAndDomainTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PrismLog.resetForTests()
    }

    func testCustomProfilePreservesMixedAMEAndMusic() {
        var config = PrismLogConfiguration.productionDefaults
        config = config.setting(.ameMatching, to: .debug)
        config = config.setting(.musicTransport, to: .notice)
        XCTAssertEqual(config.level(for: .ameMatching), .debug)
        XCTAssertEqual(config.level(for: .musicTransport), .notice)
        config.profile = .custom
        XCTAssertEqual(config.level(for: .ameMatching), .debug)
        XCTAssertEqual(config.level(for: .musicTransport), .notice)
        XCTAssertTrue(config.accepts(.debug, category: .ameMatching))
        XCTAssertFalse(config.accepts(.debug, category: .musicTransport))
    }

    func testEngineGoAndProgrammerClearEmitCatalogCodes() {
        let memory = InMemoryPrismLogSink()
        PrismLogConfigurationStore.shared.replace(.verboseAll)
        PrismLog.shared = memory
        let engine = LightingEngine(output: OutputManager())
        engine.go()
        engine.programmer.clearAll()
        let codes = Set(memory.snapshot().map(\.code))
        XCTAssertTrue(codes.contains("engine.cues.go"))
        XCTAssertTrue(codes.contains("engine.programmer.clear"))
    }

    func testMusicTransportEmitsStructuredEvents() {
        let memory = InMemoryPrismLogSink()
        PrismLogConfigurationStore.shared.replace(.verboseAll)
        PrismLog.shared = memory
        let engine = MusicalEngine()
        engine.startTransport()
        engine.continueTransport()
        engine.stopTransport()
        let codes = Set(memory.snapshot().map(\.code))
        XCTAssertTrue(codes.contains("music.transport.start"))
        XCTAssertTrue(codes.contains("music.transport.continue"))
        XCTAssertTrue(codes.contains("music.transport.stop"))
    }

    func testCommandContextUsesCatalogCodes() {
        XCTAssertEqual(PrismErrorContext.projectOpen().eventCode, "project.document.open_failed")
        XCTAssertEqual(PrismErrorContext.projectSave().eventCode, "project.document.save_failed")
        XCTAssertEqual(PrismErrorContext.projectImport().eventCode, "project.document.import_failed")
        XCTAssertEqual(PrismErrorContext.command(operation: "rename fixture", category: .uiPatch).eventCode, "patch.rename.failed")
        XCTAssertEqual(PrismErrorContext.command(operation: "commit stage layout", category: .uiStage).eventCode, "ui.stage.layout_commit_failed")
        XCTAssertEqual(PrismErrorContext.command(operation: "media", category: .uiStage).eventCode, "ui.stage.media_failed")
        XCTAssertEqual(PrismErrorContext.command(operation: "save fixture profile", category: .fixtureLibrary).eventCode, "fixture.library.save_failed")
        XCTAssertEqual(PrismErrorContext.command(operation: "update effects", category: .engineEffects).eventCode, "engine.effects.update_failed")
        XCTAssertEqual(PrismErrorContext.command(operation: "edit").eventCode, "project.command.failed")
    }

    func testDiagnosableCodeWinsOverContextEventCode() {
        struct OpenFailed: PrismDiagnosableError {
            var prismErrorCode: String { "project.open.decode_failed" }
            var userTitle: String { "Prism Couldn't Open the Show" }
            var userMessage: String { "Prism couldn't open this show because part of the file is damaged." }
            var technicalDetails: String { "decode" }
            var prismCategory: PrismLogCategory { .projectDocument }
            var prismSeverity: PrismLogLevel { .error }
        }
        let report = PrismErrorReporting.makeReport(error: OpenFailed(), context: .projectOpen())
        XCTAssertEqual(report.code, "project.open.decode_failed")
    }

    func testUnknownProjectOpenEmitsCatalogCode() {
        let memory = InMemoryPrismLogSink()
        PrismLog.shared = memory
        PrismLogConfigurationStore.shared.replace(.productionDefaults)
        let ns = NSError(domain: "test", code: 1)
        let report = PrismErrorReporting.report(error: ns, context: .projectOpen())
        XCTAssertEqual(report.code, "project.document.open_failed")
        XCTAssertEqual(memory.snapshot().first?.code, "project.document.open_failed")
    }

    func testVolumeBudgetDoesNotEmitPerTickAtProductionDefaults() {
        let memory = InMemoryPrismLogSink()
        PrismLogConfigurationStore.shared.replace(.productionDefaults)
        PrismLog.shared = memory
        for _ in 0..<200 {
            PrismLog.debug(
                .outputArtnet,
                "output.artnet.frame_summary",
                "frame",
                ratePolicy: .oncePerSecond
            )
        }
        XCTAssertEqual(memory.count, 0)
    }
}
