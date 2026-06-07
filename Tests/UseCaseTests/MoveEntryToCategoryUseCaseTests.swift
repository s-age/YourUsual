import XCTest
@testable import YourUsual

final class MoveEntryToCategoryUseCaseTests: XCTestCase {
    private var sut: MoveEntryToCategoryUseCase!
    private var entries: MockSavedEntryService!
    private var categories: MockCategoryService!
    private var mockDB: MockDB!

    override func setUp() {
        super.setUp()
        entries = MockSavedEntryService()
        categories = MockCategoryService()
        mockDB = MockDB()
        sut = MoveEntryToCategoryUseCase(entries: entries, categories: categories, db: mockDB)
    }

    override func tearDown() {
        sut = nil
        entries = nil
        categories = nil
        mockDB = nil
        super.tearDown()
    }

    private func entry(id: UUID, categoryID: UUID) -> SavedEntry {
        SavedEntry(
            id: id,
            name: "x",
            kind: .browse(BrowseEntry(url: URL(fileURLWithPath: "/x"), app: .default)),
            sortIndex: 0,
            categoryID: categoryID
        )
    }

    func test_execute_movesToKnownCategory_persistsOnce() async throws {
        let from = UUID(), to = UUID()
        let id = UUID()
        entries.listAllResult = [entry(id: id, categoryID: from)]
        categories.listAllResult = [
            EntryCategory(id: from, name: "From", sortIndex: 0),
            EntryCategory(id: to, name: "To", sortIndex: 1)
        ]
        try await sut.execute(MoveEntryToCategoryRequest(entryID: id, categoryID: to))
        XCTAssertEqual(mockDB.tx.replaceAllEntriesCallCount, 1)
    }

    func test_execute_unknownTargetCategory_throwsCategoryNotFound() async {
        let from = UUID(), missing = UUID()
        let id = UUID()
        entries.listAllResult = [entry(id: id, categoryID: from)]
        categories.listAllResult = [EntryCategory(id: from, name: "From", sortIndex: 0)]
        do {
            try await sut.execute(MoveEntryToCategoryRequest(entryID: id, categoryID: missing))
            XCTFail("Expected categoryNotFound")
        } catch {
            XCTAssertEqual(error as? OperationError, .categoryNotFound(id: missing))
        }
    }

    func test_execute_unknownTargetCategory_doesNotOpenTransaction() async {
        let from = UUID(), missing = UUID()
        let id = UUID()
        entries.listAllResult = [entry(id: id, categoryID: from)]
        categories.listAllResult = [EntryCategory(id: from, name: "From", sortIndex: 0)]
        try? await sut.execute(MoveEntryToCategoryRequest(entryID: id, categoryID: missing))
        XCTAssertEqual(mockDB.transactionCallCount, 0)
    }
}
