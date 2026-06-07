import XCTest
@testable import YourUsual

// MARK: - Mock

final class MockCategoryStore: CategoryStoreProtocol, @unchecked Sendable {
    var stored: [CategoryDTO] = []
    var fetchAllCallCount = 0

    func fetchAllCategories() throws -> [CategoryDTO] {
        fetchAllCallCount += 1
        // Emulate the real store's contract: categories come out sorted by sortIndex
        // (the repository trusts this order rather than re-sorting).
        return stored.sorted { $0.sortIndex < $1.sortIndex }
    }
}

final class CategoryRepositoryTests: XCTestCase {
    private var sut: CategoryRepository!
    private var store: MockCategoryStore!

    override func setUp() {
        super.setUp()
        store = MockCategoryStore()
        sut = CategoryRepository(store: store)
    }

    override func tearDown() {
        sut = nil
        store = nil
        super.tearDown()
    }

    // MARK: - listAll

    func test_listAll_preservesCategory() async throws {
        let cat = EntryCategory(name: "Work", sortIndex: 0)
        store.stored = [CategoryDTO(id: cat.id, name: cat.name, sortIndex: cat.sortIndex)]
        let loaded = try await sut.listAll()
        XCTAssertEqual(loaded, [cat])
    }

    // The sort itself is the store's contract (verified against the real store in
    // RegistryDatabaseCategoryCascadeTests); here we assert the repository *surfaces* that
    // order unchanged — the mock store emulates the sorted contract.
    func test_listAll_surfacesStoreSortOrder() async throws {
        store.stored = [
            CategoryDTO(id: UUID(), name: "two", sortIndex: 2),
            CategoryDTO(id: UUID(), name: "zero", sortIndex: 0),
            CategoryDTO(id: UUID(), name: "one", sortIndex: 1),
        ]
        let loaded = try await sut.listAll()
        XCTAssertEqual(loaded.map(\.sortIndex), [0, 1, 2])
    }

    func test_listAll_emptyStore_returnsEmpty() async throws {
        store.stored = []
        let loaded = try await sut.listAll()
        XCTAssertEqual(loaded, [])
    }
}
