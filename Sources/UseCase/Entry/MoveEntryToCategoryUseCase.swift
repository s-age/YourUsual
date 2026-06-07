import Foundation

final class MoveEntryToCategoryUseCase: AsyncUseCase, Sendable {
    private let entries: any SavedEntryServiceProtocol
    private let categories: any CategoryServiceProtocol
    private let db: any DBProtocol

    init(
        entries: any SavedEntryServiceProtocol,
        categories: any CategoryServiceProtocol,
        db: any DBProtocol
    ) {
        self.entries = entries
        self.categories = categories
        self.db = db
    }

    func execute(_ request: MoveEntryToCategoryRequest) async throws {
        // Read both registries before the transaction (the move transform validates the
        // target category against the known set so it can't orphan the entry). Read
        // sequentially: entry and category stores are the same `@ModelActor`
        // (`RegistryDatabase`), so the actor serializes the two fetches regardless —
        // `async let` here would pay child-task/suspension cost for zero real parallelism.
        let current = try await entries.listAll()
        let knownCategoryIDs = Set(try await categories.listAll().map(\.id))
        guard let items = try entries.moving(
            current, id: request.entryID, toCategory: request.categoryID,
            knownCategoryIDs: knownCategoryIDs
        ) else { return }
        try await db.transaction { tx in try tx.replaceAllEntries(items) }
    }
}
