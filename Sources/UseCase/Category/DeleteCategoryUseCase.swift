import Foundation

/// Deletes a category together with every entry it contains. The entry removal is
/// a SwiftData `.cascade` on `CategoryModel.entries`: when `stageReplaceAllCategories`
/// deletes the absent `CategoryModel` the cascade fires on the same transaction commit,
/// so both category and its entries disappear atomically in the single `transaction` body.
final class DeleteCategoryUseCase: AsyncUseCase, Sendable {
    private let categories: any CategoryServiceProtocol
    private let db: any DBProtocol

    init(categories: any CategoryServiceProtocol, db: any DBProtocol) {
        self.categories = categories
        self.db = db
    }

    func execute(_ request: DeleteCategoryRequest) async throws {
        let current = try await categories.listAll()
        let result = try categories.deleting(current, id: request.id)
        try await db.transaction { tx in try tx.replaceAllCategories(result) }
    }
}
