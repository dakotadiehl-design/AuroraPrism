import AuroraACP
import Foundation

public actor PrismACPExecutionDispositionStore {
    private let ledger: ACPCommandLedger

    public init(ledger: ACPCommandLedger = ACPCommandLedger()) {
        self.ledger = ledger
    }

    public func remember(_ record: ACPCommandRecord) async throws -> ACPCommandRecord {
        try await ledger.remember(record)
    }

    public func reserve(_ record: ACPCommandRecord) async -> ACPCommandReservation {
        await ledger.reserve(record)
    }

    public func complete(_ record: ACPCommandRecord) async throws -> ACPCommandRecord {
        try await ledger.complete(record)
    }

    public func lookup(
        originNodeID: String,
        commandID: String? = nil,
        idempotencyKey: String? = nil,
        originPrincipal: String? = nil,
        originInstanceID: String? = nil
    ) async -> ACPCommandRecord? {
        await ledger.lookup(
            originNodeID: originNodeID,
            commandID: commandID,
            idempotencyKey: idempotencyKey,
            originPrincipal: originPrincipal,
            originInstanceID: originInstanceID
        )
    }
}
