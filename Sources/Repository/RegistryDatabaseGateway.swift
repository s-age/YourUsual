import Foundation

/// Repository-layer `DBProtocol` implementation — the database handle the UseCase
/// calls `transaction` on. It bridges the Domain-facing `Transaction` (entity-level
/// mutation ops) to the Infrastructure `TxContextProtocol` (DTO-level synchronous
/// staging): on each `transaction`, it opens one store transaction and hands `body`
/// a `TxAdapter` that converts entity→DTO and forwards to the open `TxContextProtocol`.
///
/// The entity↔DTO conversion is Repository's job, and it happens *inside* the
/// synchronous `body` (no `await`), satisfying SwiftData's "transaction cannot
/// span await" constraint while keeping persistence types out of Domain/UseCase.
final class RegistryDatabaseGateway: DBProtocol, Sendable {
    private let runner: any TransactionRunnerProtocol

    init(runner: any TransactionRunnerProtocol) {
        self.runner = runner
    }

    func transaction<T: Sendable>(
        _ body: @Sendable (any Transaction) throws -> T
    ) async throws -> T {
        try await runner.transaction { ctx in
            try body(TxAdapter(ctx: ctx))
        }
    }

    /// Adapts the Infrastructure `TxContextProtocol` to the Domain `Transaction`,
    /// converting entities to DTOs at the boundary via the shared `*Mapper` types
    /// (the single source of truth the read path also uses). Created fresh per
    /// `transaction` and never escapes the synchronous body.
    private struct TxAdapter: Transaction {
        let ctx: any TxContextProtocol

        func registerRun(_ record: RunRecord) throws {
            try ctx.stageInsertRun(RunRecordMapper.toDTO(record))
        }

        func deleteRun(id: UUID) throws { try ctx.stageDeleteRun(id: id) }
        func deleteAllRuns(forEntry id: UUID) throws { try ctx.stageDeleteAllRuns(forEntry: id) }
        func deleteAllRuns() throws { try ctx.stageDeleteAllRuns() }

        func replaceAllEntries(_ items: [SavedEntry]) throws {
            // A recovery placeholder (`isRecovered`) must not overwrite its still-intact
            // stored row — pass its id as preserved so the store leaves that row alone.
            // The placeholder DTO is still included so a fresh import (no stored row) can
            // insert it. An entry the user actually edited/healed arrives with the flag
            // cleared, so it is written normally (the deliberate overwrite).
            let preservingIDs = Set(items.filter(\.isRecovered).map(\.id))
            try ctx.stageReplaceAllEntries(
                RegistryDTO(items: items.map(RegisteredItemMapper.toDTO)),
                preservingIDs: preservingIDs
            )
        }

        func replaceAllCategories(_ categories: [EntryCategory]) throws {
            try ctx.stageReplaceAllCategories(categories.map(CategoryMapper.toDTO))
        }

        // MARK: - PadLayout

        func registerPadLayout(_ layout: PadLayout) throws {
            try ctx.stageInsertPadLayout(PadMapper.toDTO(layout))
        }

        func editPadLayout(_ layout: PadLayout) throws {
            try ctx.stageUpdatePadLayout(PadMapper.toDTO(layout))
        }

        func deletePadLayout(id: UUID) throws {
            try ctx.stageDeletePadLayout(id: id)
        }

        // MARK: - PadCell

        func replacePadCells(layoutID: UUID, cells: [PadCell]) throws {
            try ctx.stageReplacePadCells(layoutID: layoutID, cells: cells.map(PadMapper.toDTO))
        }
    }
}
