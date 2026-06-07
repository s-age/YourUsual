import Foundation

/// Edits a category's name + menu-bar visibility. Mirrors `ReorderCategoriesUseCase`:
/// read the whole collection before the transaction, let the Domain Service compute the
/// new collection, then commit it whole-blob via `tx.replaceAllCategories`. Categories
/// have no per-record update path — the registry is a whole-blob model.
final class EditCategoryUseCase: AsyncUseCase, Sendable {
    private let categories: any CategoryServiceProtocol
    private let db: any DBProtocol

    init(categories: any CategoryServiceProtocol, db: any DBProtocol) {
        self.categories = categories
        self.db = db
    }

    func execute(_ request: EditCategoryRequest) async throws {
        let current = try await categories.listAll()
        let next = try categories.editing(
            current, id: request.id, name: request.name,
            isHiddenFromMenuBar: request.isHiddenFromMenuBar
        )
        try await db.transaction { tx in try tx.replaceAllCategories(next) }
    }
}
