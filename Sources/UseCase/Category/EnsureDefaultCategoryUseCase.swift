import Foundation

final class EnsureDefaultCategoryUseCase: AsyncUseCase, Sendable {
    private let categories: any CategoryServiceProtocol
    private let db: any DBProtocol

    init(categories: any CategoryServiceProtocol, db: any DBProtocol) {
        self.categories = categories
        self.db = db
    }

    func execute(_ request: EnsureDefaultCategoryRequest) async throws {
        let current = try await categories.listAll()
        guard let result = categories.ensuringDefault(current) else { return }
        try await db.transaction { tx in try tx.replaceAllCategories(result) }
    }
}
