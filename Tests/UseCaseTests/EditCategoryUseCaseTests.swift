import XCTest
@testable import YourUsual

final class EditCategoryUseCaseTests: XCTestCase {
    private var sut: EditCategoryUseCase!
    private var categories: MockCategoryService!
    private var mockDB: MockDB!

    override func setUp() {
        super.setUp()
        categories = MockCategoryService()
        mockDB = MockDB()
        sut = EditCategoryUseCase(categories: categories, db: mockDB)
    }

    override func tearDown() {
        sut = nil
        categories = nil
        mockDB = nil
        super.tearDown()
    }

    // MARK: - Success

    func test_execute_persistsOnce() async throws {
        let id = UUID()
        categories.listAllResult = [EntryCategory(id: id, name: "Work", sortIndex: 0)]
        try await sut.execute(EditCategoryRequest(id: id, name: "Personal", isHiddenFromMenuBar: true))
        XCTAssertEqual(mockDB.tx.replaceAllCategoriesCallCount, 1)
    }

    func test_execute_appliesNewName() async throws {
        let id = UUID()
        categories.listAllResult = [EntryCategory(id: id, name: "Work", sortIndex: 0)]
        try await sut.execute(EditCategoryRequest(id: id, name: "Personal", isHiddenFromMenuBar: false))
        XCTAssertEqual(mockDB.tx.replacedCategories?.first?.name, "Personal")
    }

    func test_execute_appliesVisibilityFlag() async throws {
        let id = UUID()
        categories.listAllResult = [EntryCategory(id: id, name: "Work", sortIndex: 0)]
        try await sut.execute(EditCategoryRequest(id: id, name: "Work", isHiddenFromMenuBar: true))
        XCTAssertEqual(mockDB.tx.replacedCategories?.first?.isHiddenFromMenuBar, true)
    }

    func test_execute_preservesSortIndex() async throws {
        let id = UUID()
        categories.listAllResult = [EntryCategory(id: id, name: "Work", sortIndex: 5)]
        try await sut.execute(EditCategoryRequest(id: id, name: "Personal", isHiddenFromMenuBar: true))
        XCTAssertEqual(mockDB.tx.replacedCategories?.first?.sortIndex, 5)
    }

    // MARK: - Not found

    func test_execute_unknownId_throwsItemNotFound() async {
        let missing = UUID()
        categories.listAllResult = [EntryCategory(id: UUID(), name: "Work", sortIndex: 0)]
        do {
            try await sut.execute(EditCategoryRequest(id: missing, name: "Personal", isHiddenFromMenuBar: false))
            XCTFail("Expected itemNotFound")
        } catch {
            XCTAssertEqual(error as? OperationError, .itemNotFound(id: missing))
        }
    }

    func test_execute_unknownId_doesNotOpenTransaction() async {
        let missing = UUID()
        categories.listAllResult = [EntryCategory(id: UUID(), name: "Work", sortIndex: 0)]
        try? await sut.execute(EditCategoryRequest(id: missing, name: "Personal", isHiddenFromMenuBar: false))
        XCTAssertEqual(mockDB.transactionCallCount, 0)
    }
}
