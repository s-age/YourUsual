import Foundation

final class RegisterCategoryUseCase: AsyncUseCase, Sendable {
    private let categories: any CategoryServiceProtocol
    private let db: any DBProtocol

    init(categories: any CategoryServiceProtocol, db: any DBProtocol) {
        self.categories = categories
        self.db = db
    }

    func execute(_ request: RegisterCategoryRequest) async throws -> CategoryResponse {
        let current = try await categories.listAll()
        let result = categories.registering(current, name: request.name)
        try await db.transaction { tx in try tx.replaceAllCategories(result.categories) }
        return CategoryResponse(from: result.registered)
    }
}
