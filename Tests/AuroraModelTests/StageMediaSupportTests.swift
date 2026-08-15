import AuroraModel
import XCTest

final class StageMediaSupportTests: XCTestCase {
    func testPackageRelativeValidationRejectsTraversal() {
        XCTAssertNil(StageMediaSupport.validatedPackageRelativePath("../etc/passwd"))
        XCTAssertNil(StageMediaSupport.validatedPackageRelativePath("/tmp/x.png"))
        XCTAssertNil(StageMediaSupport.validatedPackageRelativePath("media/../../secret"))
        XCTAssertEqual(
            StageMediaSupport.validatedPackageRelativePath("media/stage/abc.png"),
            "media/stage/abc.png"
        )
    }

    func testImportStagingThenMaterializeIntoPackage() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("AuroraC45-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // Source PNG
        let src = tmp.appendingPathComponent("floorplan.png")
        // Minimal PNG via empty data is invalid for NSImage; write via ProjectPackage path test with Data
        // Create a tiny valid-enough file for copy tests
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: src)

        let imported = try StageMediaSupport.importImage(from: src, intoOpenPackage: nil)
        XCTAssertTrue(imported.relativePath.hasPrefix("media/stage/"))
        XCTAssertTrue(fm.fileExists(atPath: imported.absoluteFileURL.path))

        var project = ShowProject.empty(name: "C45 Media")
        var layout = project.stageLayout
        layout.appendObject(StageLayoutObject(
            kind: .importedImage,
            mediaRef: imported.relativePath,
            name: "Floor",
            x: 100, y: 100, width: 200, height: 100
        ))
        project.stageLayout = layout
        project.mediaAssets.append(MediaAssetRef(name: "Floor", relativePath: imported.relativePath))

        let package = tmp.appendingPathComponent("MediaTest.aurora", isDirectory: true)
        _ = try ProjectPackage.save(project, to: package)

        let embedded = package
            .appendingPathComponent(imported.relativePath)
        XCTAssertTrue(fm.fileExists(atPath: embedded.path), "Expected \(embedded.path)")

        // Portability: load from a copied package without staging
        let copy = tmp.appendingPathComponent("Portable.aurora", isDirectory: true)
        try fm.copyItem(at: package, to: copy)
        // Remove staging file
        try? fm.removeItem(at: imported.absoluteFileURL)

        let loaded = try ProjectPackage.load(from: copy)
        let ref = loaded.stageLayout.objects.first?.mediaRef
        XCTAssertEqual(ref, imported.relativePath)
        let resolved = StageMediaSupport.resolveFileURL(mediaRef: ref!, packageRoot: copy)
        XCTAssertNotNil(resolved)
        XCTAssertTrue(fm.fileExists(atPath: resolved!.path))
    }

    func testLegacyAbsolutePathMigratesOnSave() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("AuroraC45Leg-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let legacyFile = tmp.appendingPathComponent("legacy-abs.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: legacyFile)

        var project = ShowProject.empty(name: "Legacy")
        var layout = project.stageLayout
        layout.appendObject(StageLayoutObject(
            kind: .importedImage,
            mediaRef: legacyFile.path,
            name: "Legacy",
            x: 0, y: 0, width: 100, height: 80
        ))
        project.stageLayout = layout

        let package = tmp.appendingPathComponent("Legacy.aurora", isDirectory: true)
        _ = try ProjectPackage.save(project, to: package)
        let reloaded = try ProjectPackage.load(from: package)
        let ref = try XCTUnwrap(reloaded.stageLayout.objects.first?.mediaRef)
        XCTAssertTrue(ref.hasPrefix("media/stage/"), ref)
        XCTAssertFalse(StageMediaSupport.isAbsoluteFilePath(ref))
        XCTAssertNotNil(StageMediaSupport.resolveFileURL(mediaRef: ref, packageRoot: package))
    }

    func testMissingMediaDoesNotCrashResolve() {
        let url = StageMediaSupport.resolveFileURL(
            mediaRef: "media/stage/does-not-exist.png",
            packageRoot: URL(fileURLWithPath: "/tmp")
        )
        XCTAssertNil(url)
    }

    func testSaveAsPreservesStageMedia() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("AuroraC45SA-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let src = tmp.appendingPathComponent("a.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: src)
        let imported = try StageMediaSupport.importImage(from: src, intoOpenPackage: nil)

        var project = ShowProject.empty(name: "SaveAs")
        var layout = project.stageLayout
        layout.appendObject(StageLayoutObject(
            kind: .importedImage,
            mediaRef: imported.relativePath,
            name: "A",
            x: 1, y: 1, width: 10, height: 10
        ))
        project.stageLayout = layout
        project.mediaAssets = [MediaAssetRef(name: "A", relativePath: imported.relativePath)]

        let original = tmp.appendingPathComponent("Original.aurora", isDirectory: true)
        _ = try ProjectPackage.save(project, to: original)
        let loaded = try ProjectPackage.load(from: original)

        let tour = tmp.appendingPathComponent("TourCopy.aurora", isDirectory: true)
        _ = try ProjectPackage.save(loaded, to: tour, preservingAssetsFrom: original)

        let destFile = tour.appendingPathComponent(imported.relativePath)
        XCTAssertTrue(fm.fileExists(atPath: destFile.path))
        let tourLoaded = try ProjectPackage.load(from: tour)
        XCTAssertNotNil(
            StageMediaSupport.resolveFileURL(
                mediaRef: tourLoaded.stageLayout.objects[0].mediaRef!,
                packageRoot: tour
            )
        )
    }
}
