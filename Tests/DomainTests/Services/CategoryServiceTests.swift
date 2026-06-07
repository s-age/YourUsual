import XCTest
@testable import YourUsual

// MARK: - Mock

final class MockCategoryRepository: CategoryRepositoryProtocol, @unchecked Sendable {
    var categories: [EntryCategory] = []
    var loadError: Error?

    var listAllCallCount = 0

    func listAll() throws -> [EntryCategory] {
        listAllCallCount += 1
        if let loadError { throw loadError }
        return categories
    }
}

final class CategoryServiceTests: XCTestCase {
    private var sut: CategoryService!
    private var repository: MockCategoryRepository!

    override func setUp() {
        super.setUp()
        repository = MockCategoryRepository()
        sut = CategoryService(repository: repository)
    }

    override func tearDown() {
        sut = nil
        repository = nil
        super.tearDown()
    }

    // MARK: - listAll

    func test_listAll_returnsRepositoryCategories() async throws {
        let work = EntryCategory(name: "Work", sortIndex: 1)
        repository.categories = [work]
        let result = try await sut.listAll()
        XCTAssertEqual(result, [work])
    }

    func test_listAll_callsRepositoryOnce() async throws {
        _ = try await sut.listAll()
        XCTAssertEqual(repository.listAllCallCount, 1)
    }

    // MARK: - ensuringDefault

    func test_ensuringDefault_emptyStore_seedsDefaultCategory() throws {
        let result = try XCTUnwrap(sut.ensuringDefault([]))
        XCTAssertEqual(result.first?.id, EntryCategory.defaultID)
    }

    func test_ensuringDefault_emptyStore_seedsCategoryNamedDefault() throws {
        let result = try XCTUnwrap(sut.ensuringDefault([]))
        XCTAssertEqual(result.first?.name, EntryCategory.defaultName)
    }

    func test_ensuringDefault_defaultAlreadyPresent_returnsNil() {
        XCTAssertNil(sut.ensuringDefault([EntryCategory.makeDefault()]))
    }

    // Default is only the empty-state seed: once any category exists, it is not
    // (re-)created, even when Default itself is absent.
    func test_ensuringDefault_otherCategoriesPresent_returnsNil() {
        XCTAssertNil(sut.ensuringDefault([EntryCategory(name: "Work", sortIndex: 5)]))
    }

    func test_ensuringDefault_defaultAbsentButOthersPresent_returnsNil() {
        let work = EntryCategory(name: "Work", sortIndex: 5)
        let play = EntryCategory(name: "Play", sortIndex: 6)
        XCTAssertNil(sut.ensuringDefault([work, play]))
    }

    // MARK: - registering

    func test_registering_firstCategory_assignsSortIndexZero() {
        let result = sut.registering([], name: "Work")
        XCTAssertEqual(result.registered.sortIndex, 0)
    }

    func test_registering_appendsWithMaxSortIndexPlusOne() {
        let result = sut.registering([EntryCategory(name: "A", sortIndex: 4)], name: "B")
        XCTAssertEqual(result.registered.sortIndex, 5)
    }

    func test_registering_trimsName() {
        let result = sut.registering([], name: "  Work  ")
        XCTAssertEqual(result.registered.name, "Work")
    }

    // Non-empty validation now lives in `RegisterCategoryRequest.validate()` (run by
    // the decorator), mirroring `SavedEntryService.registering`. The transform itself
    // trusts validated input and no longer guards — see RegisterCategoryRequestTests.

    // MARK: - reordering

    func test_reordering_renumbersSortIndexToMatchGivenOrder() throws {
        let a = EntryCategory(name: "A", sortIndex: 0)
        let b = EntryCategory(name: "B", sortIndex: 1)
        let c = EntryCategory(name: "C", sortIndex: 2)

        let result = try XCTUnwrap(sut.reordering([a, b, c], orderedIDs: [c.id, a.id, b.id]))

        let index = Dictionary(uniqueKeysWithValues: result.map { ($0.name, $0.sortIndex) })
        XCTAssertEqual(index["C"], 0)
        XCTAssertEqual(index["A"], 1)
        XCTAssertEqual(index["B"], 2)
    }

    func test_reordering_appendsUnmentionedCategoriesAtEnd() throws {
        let a = EntryCategory(name: "A", sortIndex: 0)
        let b = EntryCategory(name: "B", sortIndex: 1)
        let c = EntryCategory(name: "C", sortIndex: 2)

        // Only mention B and C; A should fall to the end.
        let result = try XCTUnwrap(sut.reordering([a, b, c], orderedIDs: [c.id, b.id]))

        let saved = result.sorted { $0.sortIndex < $1.sortIndex }
        XCTAssertEqual(saved.map(\.name), ["C", "B", "A"])
    }

    func test_reordering_singleElement_returnsNil() {
        let only = EntryCategory(name: "Only", sortIndex: 3)
        XCTAssertNil(sut.reordering([only], orderedIDs: [only.id]))
    }

    // MARK: - editing

    func test_editing_updatesName() throws {
        let work = EntryCategory(name: "Work", sortIndex: 1)
        let result = try sut.editing([work], id: work.id, name: "Personal", isHiddenFromMenuBar: false)
        XCTAssertEqual(result.first?.name, "Personal")
    }

    func test_editing_updatesVisibilityFlag() throws {
        let work = EntryCategory(name: "Work", sortIndex: 1)
        let result = try sut.editing([work], id: work.id, name: "Work", isHiddenFromMenuBar: true)
        XCTAssertEqual(result.first?.isHiddenFromMenuBar, true)
    }

    func test_editing_trimsName() throws {
        let work = EntryCategory(name: "Work", sortIndex: 1)
        let result = try sut.editing([work], id: work.id, name: "  Personal  ", isHiddenFromMenuBar: false)
        XCTAssertEqual(result.first?.name, "Personal")
    }

    func test_editing_preservesIDAndSortIndex() throws {
        let work = EntryCategory(name: "Work", sortIndex: 7)
        let result = try sut.editing([work], id: work.id, name: "Personal", isHiddenFromMenuBar: true)
        XCTAssertEqual(result.first?.id, work.id)
        XCTAssertEqual(result.first?.sortIndex, 7)
    }

    func test_editing_unknownId_throwsItemNotFound() {
        let work = EntryCategory(name: "Work", sortIndex: 1)
        let missing = UUID()
        do {
            _ = try sut.editing([work], id: missing, name: "Personal", isHiddenFromMenuBar: false)
            XCTFail("Expected itemNotFound")
        } catch {
            XCTAssertEqual(error as? OperationError, .itemNotFound(id: missing))
        }
    }

    // MARK: - deleting

    func test_deleting_removesCategory() throws {
        let work = EntryCategory(name: "Work", sortIndex: 1)
        let result = try sut.deleting([work], id: work.id)
        XCTAssertEqual(result, [])
    }

    func test_deleting_unknownId_throwsItemNotFound() {
        let work = EntryCategory(name: "Work", sortIndex: 1)
        let missing = UUID()
        do {
            _ = try sut.deleting([work], id: missing)
            XCTFail("Expected itemNotFound")
        } catch {
            XCTAssertEqual(error as? OperationError, .itemNotFound(id: missing))
        }
    }
}
