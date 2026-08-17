import AuroraModel
import Foundation

/// Assigns a user-facing name to one patched fixture without changing its identity or patch.
@MainActor
public final class RenameFixtureCommand: Command {
    public let name = "Rename Fixture"
    private let fixtureID: UUID
    private let newName: String
    private var previousName: String?

    public init(fixtureID: UUID, newName: String) {
        self.fixtureID = fixtureID
        self.newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func perform(context: CommandContext) throws {
        guard let index = context.project.fixtures.firstIndex(where: { $0.id == fixtureID }) else {
            throw CommandError.message("Fixture not found")
        }
        try FixtureNameValidator.validate(newName, in: context.project, excluding: [fixtureID])
        previousName = context.project.fixtures[index].name
        context.updateProject {
            $0.fixtures[index].name = newName
            $0.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let previousName,
              let index = context.project.fixtures.firstIndex(where: { $0.id == fixtureID })
        else { return }
        context.updateProject {
            $0.fixtures[index].name = previousName
            $0.metadata.modifiedAt = Date()
        }
    }
}

/// Renumber selected fixtures with contiguous display names / optional address pack.
@MainActor
public final class RenumberFixturesCommand: Command {
    public let name: String
    private let fixtureIDs: [UUID]
    private let startNumber: Int
    private let namePrefix: String
    private var previousNames: [UUID: String] = [:]

    public init(
        fixtureIDs: [UUID],
        startNumber: Int = 1,
        namePrefix: String = "Fix",
        name: String = "Renumber Fixtures"
    ) {
        self.fixtureIDs = fixtureIDs
        self.startNumber = startNumber
        self.namePrefix = namePrefix
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        let candidateNames = fixtureIDs.enumerated().map { offset, _ in
            "\(namePrefix) \(startNumber + offset)"
        }
        try FixtureNameValidator.validateBatch(
            candidateNames,
            in: context.project,
            excluding: Set(fixtureIDs)
        )
        previousNames = [:]
        var n = startNumber
        context.updateProject { project in
            for id in fixtureIDs {
                guard let idx = project.fixtures.firstIndex(where: { $0.id == id }) else { continue }
                previousNames[id] = project.fixtures[idx].name
                project.fixtures[idx].name = "\(namePrefix) \(n)"
                n += 1
            }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        context.updateProject { project in
            for (id, old) in previousNames {
                if let idx = project.fixtures.firstIndex(where: { $0.id == id }) {
                    project.fixtures[idx].name = old
                }
            }
            project.metadata.modifiedAt = Date()
        }
    }
}

/// Bulk-create N copies of a definition starting at an address.
@MainActor
public final class BulkCreateFixturesCommand: Command {
    public let name: String
    private let definitionID: UUID
    private let universeID: UUID
    private let count: Int
    private let startAddress: UInt16
    private let namePrefix: String
    private var createdIDs: [UUID] = []

    public init(
        definitionID: UUID,
        universeID: UUID,
        count: Int,
        startAddress: UInt16,
        namePrefix: String = "Unit",
        name: String = "Bulk Create Fixtures"
    ) {
        self.definitionID = definitionID
        self.universeID = universeID
        self.count = max(1, count)
        self.startAddress = startAddress
        self.namePrefix = namePrefix
        self.name = name
    }

    public var createdFixtureIDs: [UUID] { createdIDs }

    public func perform(context: CommandContext) throws {
        guard let def = context.project.definition(id: definitionID) else {
            throw CommandError.message("Definition not found")
        }
        guard context.project.universe(id: universeID) != nil else {
            throw CommandError.message("Universe not found")
        }
        let candidateNames = (0..<count).map { "\(namePrefix) \($0 + 1)" }
        try FixtureNameValidator.validateBatch(candidateNames, in: context.project)
        let footprint = def.calculatedFootprint
        createdIDs = []
        context.updateProject { project in
            var addr = startAddress
            for i in 0..<count {
                let id = UUID()
                createdIDs.append(id)
                project.fixtures.append(PatchedFixture(
                    id: id,
                    name: "\(namePrefix) \(i + 1)",
                    definitionId: definitionID,
                    universeId: universeID,
                    address: addr
                ))
                addr += footprint
            }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        let ids = Set(createdIDs)
        context.updateProject { project in
            project.fixtures.removeAll { ids.contains($0.id) }
            project.metadata.modifiedAt = Date()
        }
    }
}

/// Import patch rows from CSV (Universe,Address,End,Name,..., or minimal Universe,Address,Name,DefinitionModel).
@MainActor
public final class ImportPatchCSVCommand: Command {
    public let name: String
    private let csv: String
    private var createdIDs: [UUID] = []

    public init(csv: String, name: String = "Import Patch CSV") {
        self.csv = csv
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        createdIDs = []
        let lines = csv.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count >= 2 else { throw CommandError.message("CSV has no data rows") }
        let header = lines[0].lowercased()
        let hasHeader = header.contains("universe") || header.contains("address")
        let dataLines = hasHeader ? Array(lines.dropFirst()) : lines

        let candidateNames = dataLines.compactMap { line -> String? in
            let cols = parseCSVLine(line)
            guard cols.count >= 3 else { return nil }
            if cols.count >= 6 && header.contains("manufacturer") { return cols[3] }
            return cols[2]
        }.map { $0.isEmpty ? "Import" : $0 }
        try FixtureNameValidator.validateBatch(candidateNames, in: context.project)

        context.updateProject { project in
            for line in dataLines {
                let cols = parseCSVLine(line)
                guard cols.count >= 3 else { continue }
                // Formats:
                // Full export: Universe,Address,End,Name,Manufacturer,Model,Mode,Channels,FixtureID
                // Minimal: Universe,Address,Name,Manufacturer,Model
                let uNum = UInt16(cols[0].trimmingCharacters(in: .whitespaces)) ?? 1
                let address = UInt16(cols[1].trimmingCharacters(in: .whitespaces)) ?? 1
                let nameCol: String
                let mfr: String
                let model: String
                if cols.count >= 6 && header.contains("manufacturer") {
                    nameCol = cols[3]
                    mfr = cols[4]
                    model = cols[5]
                } else if cols.count >= 5 {
                    nameCol = cols[2]
                    mfr = cols[3]
                    model = cols[4]
                } else {
                    nameCol = cols.count > 2 ? cols[2] : "Import"
                    mfr = ""
                    model = ""
                }
                guard let universe = project.universes.first(where: { $0.number == uNum }) else { continue }
                let def: FixtureDefinition?
                if !mfr.isEmpty || !model.isEmpty {
                    def = project.fixtureDefinitions.first {
                        $0.manufacturer.caseInsensitiveCompare(mfr) == .orderedSame
                            && $0.model.caseInsensitiveCompare(model) == .orderedSame
                    } ?? project.fixtureDefinitions.first
                } else {
                    def = project.fixtureDefinitions.first
                }
                guard let definition = def else { continue }
                let id = UUID()
                createdIDs.append(id)
                project.fixtures.append(PatchedFixture(
                    id: id,
                    name: nameCol.isEmpty ? "Import" : nameCol,
                    definitionId: definition.id,
                    universeId: universe.id,
                    address: address
                ))
            }
            project.metadata.modifiedAt = Date()
        }
        if createdIDs.isEmpty {
            throw CommandError.message("No rows imported (check universe numbers and definitions)")
        }
    }

    public func undo(context: CommandContext) throws {
        let ids = Set(createdIDs)
        context.updateProject { project in
            project.fixtures.removeAll { ids.contains($0.id) }
            project.metadata.modifiedAt = Date()
        }
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }
}
