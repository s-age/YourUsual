import Foundation

final class ReadCategoriesUseCase: AsyncUseCase, Sendable {
    private let categories: any CategoryServiceProtocol

    init(categories: any CategoryServiceProtocol) {
        self.categories = categories
    }

    func execute(_ request: ReadCategoriesRequest) async throws -> [CategoryResponse] {
        let entities = try await categories.listAll()
        return entities.map(CategoryResponse.init(from:))
    }
}
