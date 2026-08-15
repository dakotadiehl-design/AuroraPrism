import AuroraCore
import AuroraModel
import XCTest

final class PatchReportTests: XCTestCase {
    func testCSVContainsFixtures() {
        let project = ShowProject.sample()
        let csv = PatchReport.csv(project: project)
        XCTAssertTrue(csv.contains("Universe,Address"))
        XCTAssertTrue(csv.contains("SL Dim 1") || csv.contains(project.fixtures.first?.name ?? "___"))
    }

    func testHumanReadableNonEmpty() {
        let report = PatchReport.humanReadable(project: .sample())
        XCTAssertTrue(report.contains("Aurora Patch Report"))
        XCTAssertTrue(report.contains("Universe"))
    }
}
