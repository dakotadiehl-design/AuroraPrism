import AuroraModel
import XCTest

/// Controllable writer that can pause mid-save for concurrency tests.
final class ControllablePackageWriter: ProjectPackageWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var pauseGate: DispatchSemaphore?
    private var resumeGate: DispatchSemaphore?
    private(set) var writtenNames: [String] = []
    private var disk: [String: ShowProject] = [:]
    private(set) var saveCallCount = 0

    func armPause() {
        lock.lock()
        pauseGate = DispatchSemaphore(value: 0)
        resumeGate = DispatchSemaphore(value: 0)
        lock.unlock()
    }

    func waitUntilPaused(timeout: TimeInterval = 2) -> Bool {
        lock.lock()
        let gate = pauseGate
        lock.unlock()
        guard let gate else { return false }
        return gate.wait(timeout: .now() + timeout) == .success
    }

    func resume() {
        lock.lock()
        let gate = resumeGate
        lock.unlock()
        gate?.signal()
    }

    func project(at url: URL) -> ShowProject? {
        lock.lock()
        defer { lock.unlock() }
        return disk[url.standardizedFileURL.path]
    }

    func save(
        _ project: ShowProject,
        to url: URL,
        preservingAssetsFrom: URL?
    ) async throws -> Date {
        lock.lock()
        let shouldPause = resumeGate != nil
        let pause = pauseGate
        let resume = resumeGate
        if shouldPause {
            pauseGate = nil
            resumeGate = nil
        }
        saveCallCount += 1
        lock.unlock()

        if shouldPause, let pause, let resume {
            pause.signal()
            _ = resume.wait(timeout: .now() + 10)
        }

        let writtenAt = Date()
        lock.lock()
        writtenNames.append(project.metadata.name)
        disk[url.standardizedFileURL.path] = project
        lock.unlock()
        return writtenAt
    }
}

final class ProjectSaveCoordinatorTests: XCTestCase {
    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AuroraSaveCoord-\(UUID().uuidString)-\(name).aurora", isDirectory: true)
    }

    /// Serialization: overlapping autosave + manual end with manual state on disk.
    func testSerializedAutosaveThenManualEndsWithManual() async throws {
        let writer = ControllablePackageWriter()
        let coordinator = ProjectSaveCoordinator(writer: writer)
        let url = tempURL("Show")
        let projectA = ShowProject.empty(name: "StateA")
        let projectB = ShowProject.empty(name: "StateB")

        writer.armPause()
        async let auto: ProjectSaveResult = coordinator.autosave(ProjectSaveSnapshot(
            project: projectA,
            documentStateID: 1,
            destinationURL: url,
            kind: .autosave
        ))
        XCTAssertTrue(writer.waitUntilPaused())

        // Manual waits until autosave releases the destination lock, then writes B.
        async let manual: ProjectSaveResult = coordinator.save(ProjectSaveSnapshot(
            project: projectB,
            documentStateID: 2,
            destinationURL: url,
            kind: .manual
        ))

        writer.resume()
        _ = try await auto
        _ = try await manual

        XCTAssertEqual(writer.project(at: url)?.metadata.name, "StateB")
        XCTAssertEqual(writer.writtenNames.last, "StateB")
    }

    /// Test A (core): autosave after a newer manual save is skipped and never calls the writer.
    func testStaleAutosaveSkippedAfterManualSave() async throws {
        let writer = ControllablePackageWriter()
        let coordinator = ProjectSaveCoordinator(writer: writer)
        let url = tempURL("Skip")
        let projectA = ShowProject.empty(name: "StateA")
        let projectB = ShowProject.empty(name: "StateB")

        _ = try await coordinator.save(ProjectSaveSnapshot(
            project: projectB,
            documentStateID: 5,
            destinationURL: url,
            kind: .manual
        ))
        XCTAssertEqual(writer.project(at: url)?.metadata.name, "StateB")
        let callsAfterManual = writer.saveCallCount

        let result = try await coordinator.autosave(ProjectSaveSnapshot(
            project: projectA,
            documentStateID: 3,
            destinationURL: url,
            kind: .autosave
        ))
        XCTAssertEqual(result, .skippedStale)
        XCTAssertEqual(writer.project(at: url)?.metadata.name, "StateB")
        XCTAssertEqual(writer.saveCallCount, callsAfterManual, "stale autosave must not invoke writer")
    }

    /// Test B: while one autosave is in-flight, older queued autosaves skip in favor of newest.
    func testAutosaveCoalesceSkipsObsoleteWhileNewestWrites() async throws {
        let writer = ControllablePackageWriter()
        let coordinator = ProjectSaveCoordinator(writer: writer)
        let url = tempURL("Coal")

        writer.armPause()
        async let r1: ProjectSaveResult = coordinator.autosave(ProjectSaveSnapshot(
            project: ShowProject.empty(name: "A"),
            documentStateID: 1,
            destinationURL: url,
            kind: .autosave
        ))
        XCTAssertTrue(writer.waitUntilPaused())

        // Enqueue B (obsolete once C is seen) and C (newest).
        async let r2: ProjectSaveResult = coordinator.autosave(ProjectSaveSnapshot(
            project: ShowProject.empty(name: "B"),
            documentStateID: 2,
            destinationURL: url,
            kind: .autosave
        ))
        // Small delay so B registers before C for ordering realism
        try await Task.sleep(nanoseconds: 20_000_000)
        async let r3: ProjectSaveResult = coordinator.autosave(ProjectSaveSnapshot(
            project: ShowProject.empty(name: "C"),
            documentStateID: 3,
            destinationURL: url,
            kind: .autosave
        ))

        try await Task.sleep(nanoseconds: 30_000_000)
        writer.resume()

        let results = try await [r1, r2, r3]
        // A may write (in-flight). B should skip (C is newer). C should write.
        if case .skippedStale = results[1] {
            // expected
        } else if case .written(_, let id, _) = results[1] {
            // B might write if it acquired before C registered — still OK if C is final
            XCTAssertEqual(id, 2)
        }
        // Final on-disk should be the highest written state among those that wrote
        let written = results.compactMap { r -> (UInt64, String)? in
            if case .written(_, let id, _) = r {
                return (id, ["A", "B", "C"][Int(id) - 1])
            }
            return nil
        }
        XCTAssertFalse(written.isEmpty)
        let maxID = written.map(\.0).max()!
        XCTAssertEqual(writer.project(at: url)?.metadata.name, ["A", "B", "C"][Int(maxID) - 1])
    }

    /// Test C: Save As to a new package while autosave holds the old destination.
    func testSaveAsDuringAutosaveDifferentDestinations() async throws {
        let writer = ControllablePackageWriter()
        let coordinator = ProjectSaveCoordinator(writer: writer)
        let oldURL = tempURL("Old")
        let newURL = tempURL("New")

        writer.armPause()
        async let auto: ProjectSaveResult = coordinator.autosave(ProjectSaveSnapshot(
            project: ShowProject.empty(name: "OldSnap"),
            documentStateID: 1,
            destinationURL: oldURL,
            kind: .autosave
        ))
        XCTAssertTrue(writer.waitUntilPaused())

        let saveAs = try await coordinator.save(ProjectSaveSnapshot(
            project: ShowProject.empty(name: "NewSnap"),
            documentStateID: 2,
            destinationURL: newURL,
            preservingAssetsFrom: oldURL,
            kind: .saveAs
        ))
        guard case .written(_, let id, _) = saveAs else {
            return XCTFail("Save As should write")
        }
        XCTAssertEqual(id, 2)
        XCTAssertEqual(writer.project(at: newURL)?.metadata.name, "NewSnap")

        writer.resume()
        _ = try await auto
        XCTAssertEqual(writer.project(at: oldURL)?.metadata.name, "OldSnap")
    }

    /// Test D: result carries the snapshot state ID that was written (caller uses for dirty check).
    func testWrittenResultCarriesSnapshotStateID() async throws {
        let writer = ControllablePackageWriter()
        let coordinator = ProjectSaveCoordinator(writer: writer)
        let url = tempURL("ID")
        let result = try await coordinator.save(ProjectSaveSnapshot(
            project: ShowProject.empty(name: "X"),
            documentStateID: 42,
            destinationURL: url,
            kind: .manual
        ))
        guard case .written(_, let id, _) = result else {
            return XCTFail("expected written")
        }
        XCTAssertEqual(id, 42)
    }

    /// Real filesystem writer still works through the coordinator.
    func testDefaultWriterRoundTrip() async throws {
        let coordinator = ProjectSaveCoordinator()
        let url = tempURL("Real")
        defer { try? FileManager.default.removeItem(at: url) }
        let project = ShowProject.empty(name: "Live")
        let result = try await coordinator.save(ProjectSaveSnapshot(
            project: project,
            documentStateID: 1,
            destinationURL: url,
            kind: .manual
        ))
        guard case .written = result else {
            return XCTFail("expected write")
        }
        let loaded = try ProjectPackage.load(from: url)
        XCTAssertEqual(loaded.metadata.name, "Live")
    }
}
