import Foundation

// MARK: - Save snapshot / result

/// Why a package write was requested (BLOCKER-1).
public enum ProjectSaveKind: String, Sendable, Equatable {
    case manual
    case saveAs
    case autosave
}

/// Immutable capture of document state for a package write.
public struct ProjectSaveSnapshot: Sendable, Equatable {
    public var project: ShowProject
    public var documentStateID: UInt64
    public var destinationURL: URL
    public var preservingAssetsFrom: URL?
    public var kind: ProjectSaveKind

    public init(
        project: ShowProject,
        documentStateID: UInt64,
        destinationURL: URL,
        preservingAssetsFrom: URL? = nil,
        kind: ProjectSaveKind
    ) {
        self.project = project
        self.documentStateID = documentStateID
        self.destinationURL = destinationURL
        self.preservingAssetsFrom = preservingAssetsFrom
        self.kind = kind
    }
}

public enum ProjectSaveResult: Sendable, Equatable {
    /// Package was written with this document state ID.
    case written(modifiedAt: Date, stateID: UInt64, destination: URL)
    /// Skipped because a newer write for the destination already completed or is preferred.
    case skippedStale
}

// MARK: - Writer injection

/// Injectable package writer (real FS or test double).
public protocol ProjectPackageWriting: Sendable {
    func save(
        _ project: ShowProject,
        to url: URL,
        preservingAssetsFrom: URL?
    ) async throws -> Date
}

/// Default writer → `ProjectPackage.save`.
public struct DefaultProjectPackageWriter: ProjectPackageWriting {
    public init() {}

    public func save(
        _ project: ShowProject,
        to url: URL,
        preservingAssetsFrom: URL?
    ) async throws -> Date {
        try ProjectPackage.save(project, to: url, preservingAssetsFrom: preservingAssetsFrom)
    }
}

// MARK: - Coordinator

/// Serializes all writes to the same `.aurora` destination (BLOCKER-1).
///
/// Correctness boundary is **before** filesystem replacement: a stale autosave never
/// calls the writer after a newer manual save has completed for that path.
public actor ProjectSaveCoordinator {
    private let writer: any ProjectPackageWriting

    /// Per-destination gate (standardized path).
    private var busy: [String: Bool] = [:]
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    /// Last successfully written state for each destination.
    private var lastWrite: [String: (stateID: UInt64, kind: ProjectSaveKind)] = [:]

    /// Highest autosave state ID currently enqueued/in-flight for coalesce.
    private var highestAutosaveSeen: [String: UInt64] = [:]

    public init(writer: any ProjectPackageWriting = DefaultProjectPackageWriter()) {
        self.writer = writer
    }

    /// Manual Save / Save As — always attempts write after acquiring the destination lock.
    public func save(_ snapshot: ProjectSaveSnapshot) async throws -> ProjectSaveResult {
        precondition(snapshot.kind == .manual || snapshot.kind == .saveAs)
        return try await perform(snapshot)
    }

    /// Autosave — may skip if stale relative to a completed newer write or a newer autosave.
    public func autosave(_ snapshot: ProjectSaveSnapshot) async throws -> ProjectSaveResult {
        precondition(snapshot.kind == .autosave)
        let key = Self.key(snapshot.destinationURL)

        // Coalesce early: if a strictly newer autosave was already registered, drop this one.
        if let high = highestAutosaveSeen[key], snapshot.documentStateID < high {
            return .skippedStale
        }
        highestAutosaveSeen[key] = max(highestAutosaveSeen[key] ?? 0, snapshot.documentStateID)

        // If a completed write already has a higher state ID, skip before waiting.
        if let last = lastWrite[key], last.stateID > snapshot.documentStateID {
            return .skippedStale
        }

        return try await perform(snapshot)
    }

    // MARK: - Internals

    private func perform(_ snapshot: ProjectSaveSnapshot) async throws -> ProjectSaveResult {
        let key = Self.key(snapshot.destinationURL)
        await acquire(key)
        defer { release(key) }

        // Re-check after waiting for the destination lock.
        if snapshot.kind == .autosave {
            if let last = lastWrite[key], last.stateID > snapshot.documentStateID {
                return .skippedStale
            }
            if let high = highestAutosaveSeen[key], high > snapshot.documentStateID {
                return .skippedStale
            }
        }

        let writtenAt = try await writer.save(
            snapshot.project,
            to: snapshot.destinationURL,
            preservingAssetsFrom: snapshot.preservingAssetsFrom
        )

        lastWrite[key] = (snapshot.documentStateID, snapshot.kind)

        if snapshot.kind == .autosave,
           highestAutosaveSeen[key] == snapshot.documentStateID {
            // Allow future autosaves with equal-or-higher IDs; clear watermark if we were the tip.
            highestAutosaveSeen[key] = nil
        }

        return .written(
            modifiedAt: writtenAt,
            stateID: snapshot.documentStateID,
            destination: snapshot.destinationURL
        )
    }

    private func acquire(_ key: String) async {
        if busy[key] == true {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                waiters[key, default: []].append(cont)
            }
        }
        busy[key] = true
    }

    private func release(_ key: String) {
        if var queue = waiters[key], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[key] = queue.isEmpty ? nil : queue
            // Keep busy = true for the next waiter.
            next.resume()
        } else {
            busy[key] = false
            waiters[key] = nil
        }
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
