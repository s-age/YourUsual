import Foundation

/// One-shot import of the legacy `registry.json` into the SwiftData store, run at
/// boot. **Owns the transaction boundary** — the same shape as
/// `EnsureDefaultCategoryUseCase`: the Domain service reads + decides, this use case
/// commits the returned collection in one `transaction`. Idempotent: the service
/// returns nil (no-op) when the store is already populated or no legacy file exists,
/// so a commit happens only on a genuine first import.
final class MigrateLegacyRegistryUseCase: AsyncUseCase, Sendable {
    private let migration: any LegacyMigrationServiceProtocol
    private let db: any DBProtocol

    init(migration: any LegacyMigrationServiceProtocol, db: any DBProtocol) {
        self.migration = migration
        self.db = db
    }

    func execute(_ request: MigrateLegacyRegistryRequest) async throws {
        guard let items = try await migration.importingLegacy() else { return }
        try await db.transaction { tx in try tx.replaceAllEntries(items) }
    }
}
