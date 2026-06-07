import Foundation

final class ReorderCategoriesUseCase: AsyncUseCase, Sendable {
    private let categories: any CategoryServiceProtocol
    private let db: any DBProtocol

    init(categories: any CategoryServiceProtocol, db: any DBProtocol) {
        self.categories = categories
        self.db = db
    }

    func execute(_ request: ReorderCategoriesRequest) async throws {
        let current = try await categories.listAll()
        guard let result = categories.reordering(current, orderedIDs: request.orderedIDs) else { return }
        try await db.transaction { tx in try tx.replaceAllCategories(result) }
    }
}
