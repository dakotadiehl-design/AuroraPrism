import AuroraModel
import Foundation

/// Planned batch patch placement (Wave 2 — single validation path for drag / click / next-free).
public struct PatchBatchPlan: Equatable, Sendable {
    public var definitionID: UUID
    public var universeID: UUID
    public var startAddress: UInt16
    public var quantity: Int
    public var namePrefix: String
    public var nameStartNumber: Int
    public var footprint: UInt16
    /// Per-fixture planned start addresses.
    public var starts: [UInt16]
    public var isValid: Bool
    public var rejectionReason: String?

    public init(
        definitionID: UUID,
        universeID: UUID,
        startAddress: UInt16,
        quantity: Int,
        namePrefix: String,
        footprint: UInt16,
        starts: [UInt16],
        isValid: Bool,
        rejectionReason: String? = nil,
        nameStartNumber: Int = 1
    ) {
        self.definitionID = definitionID
        self.universeID = universeID
        self.startAddress = startAddress
        self.quantity = quantity
        self.namePrefix = namePrefix
        self.nameStartNumber = nameStartNumber
        self.footprint = footprint
        self.starts = starts
        self.isValid = isValid
        self.rejectionReason = rejectionReason
    }
}

/// Shared planner for all three Patch placement workflows.
public enum PatchBatchPlanner {
    /// Build a plan for `quantity` fixtures of `definition` starting at `startAddress`.
    public static func plan(
        project: ShowProject,
        definitionID: UUID,
        universeID: UUID,
        startAddress: UInt16,
        quantity: Int,
        namePrefix: String
    ) -> PatchBatchPlan {
        let qty = max(1, quantity)
        guard let def = project.definition(id: definitionID) else {
            return invalid(definitionID, universeID, startAddress, qty, namePrefix, 0, "Profile missing")
        }
        let footprint = max(def.channelCount, def.calculatedFootprint)
        guard footprint >= 1 else {
            return invalid(definitionID, universeID, startAddress, qty, namePrefix, footprint, "Invalid footprint")
        }
        guard project.universe(id: universeID) != nil else {
            return invalid(definitionID, universeID, startAddress, qty, namePrefix, footprint, "Universe missing")
        }
        var starts: [UInt16] = []
        starts.reserveCapacity(qty)
        var cursor = Int(startAddress)
        let capacity = Int(project.universe(id: universeID)?.channelCount ?? 512)
        for _ in 0..<qty {
            if cursor < 1 {
                return invalid(definitionID, universeID, startAddress, qty, namePrefix, footprint, "Invalid address")
            }
            let end = cursor + Int(footprint) - 1
            if end > capacity {
                return invalid(definitionID, universeID, startAddress, qty, namePrefix, footprint, "Past channel \(capacity)")
            }
            // Temporary fixture for canPlace against project + already-planned siblings.
            var proposed = project
            for (i, s) in starts.enumerated() {
                proposed.fixtures.append(PatchedFixture(
                    name: "\(namePrefix) \(i + 1)",
                    definitionId: definitionID,
                    universeId: universeID,
                    address: s
                ))
            }
            let trial = PatchedFixture(
                name: "trial",
                definitionId: definitionID,
                universeId: universeID,
                address: UInt16(cursor)
            )
            if !proposed.canPlace(fixture: trial) {
                return invalid(definitionID, universeID, startAddress, qty, namePrefix, footprint, "Overlap at \(cursor)")
            }
            starts.append(UInt16(cursor))
            cursor = end + 1
        }
        let resolvedPrefix = namePrefix.isEmpty ? "Fix" : namePrefix
        return PatchBatchPlan(
            definitionID: definitionID,
            universeID: universeID,
            startAddress: startAddress,
            quantity: qty,
            namePrefix: resolvedPrefix,
            footprint: footprint,
            starts: starts,
            isValid: true,
            rejectionReason: nil,
            nameStartNumber: nextAvailableNameStart(project: project, prefix: resolvedPrefix, quantity: qty)
        )
    }

    private static func nextAvailableNameStart(project: ShowProject, prefix: String, quantity: Int) -> Int {
        let existing = Set(project.fixtures.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase })
        var start = 1
        while true {
            let available = (0..<quantity).allSatisfy {
                !existing.contains("\(prefix) \(start + $0)".localizedLowercase)
            }
            if available { return start }
            start += 1
        }
    }

    /// Next-free: first contiguous range that fits the whole batch.
    public static func planNextFree(
        project: ShowProject,
        definitionID: UUID,
        universeID: UUID,
        quantity: Int,
        namePrefix: String
    ) -> PatchBatchPlan {
        let qty = max(1, quantity)
        guard let def = project.definition(id: definitionID) else {
            return invalid(definitionID, universeID, 1, qty, namePrefix, 0, "Profile missing")
        }
        let footprint = max(def.channelCount, def.calculatedFootprint)
        let batchWidth = Int(footprint) * qty
        guard let universe = project.universe(id: universeID), batchWidth >= 1 else {
            return invalid(definitionID, universeID, 1, qty, namePrefix, footprint, "Cannot place batch")
        }
        let capacity = Int(universe.channelCount)
        // Scan candidate starts.
        var candidate = 1
        while candidate + batchWidth - 1 <= capacity {
            let plan = plan(
                project: project,
                definitionID: definitionID,
                universeID: universeID,
                startAddress: UInt16(candidate),
                quantity: qty,
                namePrefix: namePrefix
            )
            if plan.isValid { return plan }
            candidate += 1
        }
        return invalid(definitionID, universeID, 1, qty, namePrefix, footprint, "No contiguous free range for batch")
    }

    private static func invalid(
        _ def: UUID, _ uni: UUID, _ start: UInt16, _ qty: Int, _ prefix: String, _ fp: UInt16, _ reason: String
    ) -> PatchBatchPlan {
        PatchBatchPlan(
            definitionID: def,
            universeID: uni,
            startAddress: start,
            quantity: qty,
            namePrefix: prefix,
            footprint: fp,
            starts: [],
            isValid: false,
            rejectionReason: reason
        )
    }
}

/// Pure geometry for wrapped DMX universe (32 ch/row default).
public enum DMXUniverseGridLayout {
    public static let channelsPerRowDefault = 32

    /// Row/col for 1-based address (0-based indices).
    public static func cell(address: UInt16, channelsPerRow: Int = channelsPerRowDefault) -> (row: Int, col: Int) {
        let a = max(1, Int(address))
        let idx = a - 1
        return (idx / channelsPerRow, idx % channelsPerRow)
    }

    /// Segments of a contiguous footprint that may wrap across rows.
    public static func segments(
        start: UInt16,
        footprint: UInt16,
        channelsPerRow: Int = channelsPerRowDefault
    ) -> [(row: Int, colStart: Int, colEnd: Int, addressStart: UInt16, addressEnd: UInt16)] {
        guard footprint >= 1, start >= 1 else { return [] }
        var result: [(Int, Int, Int, UInt16, UInt16)] = []
        var addr = Int(start)
        let end = Int(start) + Int(footprint) - 1
        while addr <= end {
            let (row, col) = cell(address: UInt16(addr), channelsPerRow: channelsPerRow)
            let rowEndAddr = (row + 1) * channelsPerRow
            let segEnd = min(end, rowEndAddr)
            let colEnd = cell(address: UInt16(segEnd), channelsPerRow: channelsPerRow).col
            result.append((row, col, colEnd, UInt16(addr), UInt16(segEnd)))
            addr = segEnd + 1
        }
        return result
    }
}
