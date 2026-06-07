import Foundation

/// The database handle the UseCase owns, exposing the transaction boundary as
/// `db.transaction { tx in … }`. The closure **commits on success and rolls back
/// if it throws**, returning its value. This is the *single* begin→commit/rollback
/// site in the app; no other layer opens a transaction.
///
/// `body` is **synchronous** by a hard SwiftData constraint (a transaction
/// cannot span `await`). All reads, validation, resolution and pure computation
/// run **before** `transaction`; the `Transaction` token only *applies* writes
/// that were already resolved. Mutation ops exist solely on `Transaction`, and a
/// `Transaction` is obtainable solely inside this closure — so "mutate without a
/// transaction" is uncompilable.
protocol DBProtocol: Sendable {
    func transaction<T: Sendable>(
        _ body: @Sendable (any Transaction) throws -> T
    ) async throws -> T
}

/// The mutation capability token. It exists only inside `DBProtocol.transaction`'s
/// closure; every mutation of the **persisted SwiftData registry** (entry / category /
/// run-history) — even a single insert/delete — goes through it. Operations are
/// synchronous staging on the open transaction (entity-level; no persistence types
/// leak here). Reads are intentionally absent: fetch before `transaction`.
///
/// Preference blobs (`UserDefaults` settings, `SMAppService` login item) persist on a
/// separate, non-SwiftData substrate this token does not cover — `transaction` cannot
/// roll them back. Each is a single-step write owned by its settings Service. See
/// `arch.md` → "Transaction control" (carve-out).
protocol Transaction: Sendable {
    // RunHistory
    func registerRun(_ record: RunRecord) throws
    func deleteRun(id: UUID) throws
    func deleteAllRuns(forEntry id: UUID) throws
    func deleteAllRuns() throws

    // Entry registry — whole-collection reconcile
    func replaceAllEntries(_ items: [SavedEntry]) throws

    // Category registry — whole-collection reconcile
    func replaceAllCategories(_ categories: [EntryCategory]) throws

    // PadLayout — per-record
    func registerPadLayout(_ layout: PadLayout) throws
    func editPadLayout(_ layout: PadLayout) throws
    func deletePadLayout(id: UUID) throws

    // PadCell — per-layout atomic replacement
    func replacePadCells(layoutID: UUID, cells: [PadCell]) throws
}
