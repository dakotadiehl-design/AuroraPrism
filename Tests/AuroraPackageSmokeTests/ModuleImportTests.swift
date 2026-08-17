import AuroraCore
import AuroraDiagnostics
import AuroraEngine
import AuroraFixtureLib
import AuroraMIDI
import AuroraModel
import AuroraMusical
import AuroraOutput
import AuroraUI
import XCTest

/// Smoke-tests that every library product imports and exposes the PR1 identity API.
final class ModuleImportTests: XCTestCase {
    func testAllLibraryIdentities() {
        let expected: [(String, String)] = [
            (AuroraModelModule.name, "AuroraModel"),
            (AuroraCoreModule.name, "AuroraCore"),
            (AuroraEngineModule.name, "AuroraEngine"),
            (AuroraMIDIModule.name, "AuroraMIDI"),
            (AuroraMusicalModule.name, "AuroraMusical"),
            (AuroraOutputModule.name, "AuroraOutput"),
            (AuroraFixtureLibModule.name, "AuroraFixtureLib"),
            (AuroraDiagnosticsModule.name, "AuroraDiagnostics"),
            (AuroraUIModule.name, "AuroraUI"),
        ]

        for (actual, expectedName) in expected {
            XCTAssertEqual(actual, expectedName)
        }
    }

    func testEngineDependencyTouchpoints() {
        XCTAssertEqual(AuroraEngineModule.modelModuleName, "AuroraModel")
        XCTAssertEqual(AuroraEngineModule.outputModuleName, "AuroraOutput")
    }

    func testFixtureLibDependsOnModel() {
        XCTAssertEqual(AuroraFixtureLibModule.modelModuleName, "AuroraModel")
    }

    func testScaffoldCatalogNonEmpty() {
        let modules = ScaffoldModuleCatalog.modules
        XCTAssertFalse(modules.isEmpty)
        XCTAssertTrue(modules.contains { $0.name == "AuroraModel" })
        XCTAssertTrue(modules.contains { $0.name == "AuroraUI" })
    }
}
