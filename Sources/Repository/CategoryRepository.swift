import Foundation

final class CategoryRepository: CategoryRepositoryProtocol, Sendable {
    private let store: any CategoryStoreProtocol

    init(store: any CategoryStoreProtocol) {
        self.store = store
    }

    func listAll() async throws -> [EntryCategory] {
        // Order is the store's contract (sorted by sortIndex); the repository only maps.
        try await store.fetchAllCategories()
            .map(CategoryMapper.toEntity)
    }
}
