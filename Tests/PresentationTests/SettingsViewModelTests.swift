import XCTest
@testable import YourUsual

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private var mockFetch: MockReadEntriesUseCase!
    private var mockCategories: MockReadCategoriesUseCase!
    private var mockRegisterCategory: MockRegisterCategoryUseCase!
    private var mockReorderCategories: MockReorderCategoriesUseCase!
    private var mockDeleteCategory: MockDeleteCategoryUseCase!
    private var mockEditCategory: MockEditCategoryUseCase!
    private var mockDelete: MockDeleteEntryUseCase!
    private var mockReorder: MockReorderEntriesUseCase!
    private var mockMove: MockMoveEntryToCategoryUseCase!
    private var registry: RegistryViewModel!
    private var sut: SettingsViewModel!

    override func setUp() {
        super.setUp()
        mockFetch = MockReadEntriesUseCase()
        mockCategories = MockReadCategoriesUseCase()
        mockRegisterCategory = MockRegisterCategoryUseCase()
        mockReorderCategories = MockReorderCategoriesUseCase()
        mockDeleteCategory = MockDeleteCategoryUseCase()
        mockEditCategory = MockEditCategoryUseCase()
        mockDelete = MockDeleteEntryUseCase()
        mockReorder = MockReorderEntriesUseCase()
        mockMove = MockMoveEntryToCategoryUseCase()
        registry = RegistryViewModel(readEntries: mockFetch, readCategories: mockCategories)
        sut = SettingsViewModel(
            registry: registry,
            registerCategory: mockRegisterCategory,
            reorderCategories: mockReorderCategories,
            deleteCategory: mockDeleteCategory,
            editCategory: mockEditCategory,
            deleteEntry: mockDelete,
            reorderEntries: mockReorder,
            moveEntryToCategory: mockMove,
            appIcons: makeTestAppIconCache()
        )
    }

    override func tearDown() {
        sut = nil
        registry = nil
        mockFetch = nil
        mockCategories = nil
        mockRegisterCategory = nil
        mockReorderCategories = nil
        mockDeleteCategory = nil
        mockEditCategory = nil
        mockDelete = nil
        mockReorder = nil
        mockMove = nil
        super.tearDown()
    }

    // MARK: - load()

    func testLoad_setsItemsFromFetchUseCase() async {
        let items = [ItemFixtures.make(name: "A")]
        mockFetch.result = items

        await sut.load()

        XCTAssertEqual(sut.items, items)
    }

    func testLoad_sortsCategoriesBySortIndex() async {
        mockCategories.result = [
            CategoryResponse(id: UUID(), name: "Second", sortIndex: 1),
            CategoryResponse(id: UUID(), name: "First", sortIndex: 0)
        ]

        await sut.load()

        XCTAssertEqual(sut.categories.map(\.name), ["First", "Second"])
    }

    func testLoad_selectsFirstCategoryByDefault() async {
        let first = CategoryResponse(id: UUID(), name: "First", sortIndex: 0)
        mockCategories.result = [
            CategoryResponse(id: UUID(), name: "Second", sortIndex: 1),
            first
        ]

        await sut.load()

        XCTAssertEqual(sut.selectedCategoryID, first.id)
    }

    func testLoad_recoversSelectionWhenSelectedCategoryRemoved() async {
        let surviving = CategoryResponse(id: UUID(), name: "Surviving", sortIndex: 0)
        sut.selection = .category(UUID())  // a category that no longer exists
        mockCategories.result = [surviving]

        await sut.load()

        XCTAssertEqual(sut.selectedCategoryID, surviving.id)
    }

    // MARK: - visibleItems

    func testVisibleItems_returnsOnlyEntriesOfSelectedCategory() async {
        let work = CategoryResponse(id: UUID(), name: "Work", sortIndex: 0)
        let home = CategoryResponse(id: UUID(), name: "Home", sortIndex: 1)
        let workItem = ItemFixtures.make(name: "Work item", categoryID: work.id)
        mockCategories.result = [work, home]
        mockFetch.result = [
            workItem,
            ItemFixtures.make(name: "Home item", categoryID: home.id)
        ]
        await sut.load()

        sut.selection = .category(work.id)

        XCTAssertEqual(sut.visibleItems, [workItem])
    }

    func testVisibleItems_foldsOrphanEntriesIntoFirstCategory() async {
        let first = CategoryResponse(id: UUID(), name: "First", sortIndex: 0)
        let orphan = ItemFixtures.make(name: "Orphan", categoryID: UUID())
        mockCategories.result = [first]
        mockFetch.result = [orphan]
        await sut.load()

        sut.selection = .category(first.id)

        XCTAssertEqual(sut.visibleItems, [orphan])
    }

    // MARK: - delete(_:)

    func testDelete_callsDeleteUseCaseOnce() async {
        await sut.delete(ItemFixtures.make())

        XCTAssertEqual(mockDelete.callCount, 1)
    }

    func testDelete_passesItemID() async {
        let item = ItemFixtures.make()

        await sut.delete(item)

        XCTAssertEqual(mockDelete.deletedID, item.id)
    }

    func testDelete_whenUseCaseFails_surfacesActionError() async {
        mockDelete.error = OperationError.persistenceFailed(reason: "disk full")

        await sut.delete(ItemFixtures.make())

        XCTAssertEqual(sut.actionError, OperationError.persistenceFailed(reason: "disk full").localizedDescription)
    }

    func testDelete_whenUseCaseSucceeds_leavesActionErrorNil() async {
        await sut.delete(ItemFixtures.make())

        XCTAssertNil(sut.actionError)
    }

    func testDelete_reloadsRegistryAfterMutation() async {
        let before = mockFetch.callCount

        await sut.delete(ItemFixtures.make())

        // Reload reconciles against the store: delete re-reads the shared registry
        // (one extra readEntries call), refreshing both the settings and menu-bar lists.
        XCTAssertEqual(mockFetch.callCount, before + 1)
    }

    // MARK: - reorder(draggedID:onto:)

    func testReorder_callsReorderWithNewOrder() async {
        let work = CategoryResponse(id: UUID(), name: "Work", sortIndex: 0)
        let a = ItemFixtures.make(name: "A", categoryID: work.id)
        let b = ItemFixtures.make(name: "B", categoryID: work.id)
        let c = ItemFixtures.make(name: "C", categoryID: work.id)
        mockCategories.result = [work]
        mockFetch.result = [a, b, c]
        await sut.load()
        sut.selection = .category(work.id)

        // Drop C onto A — C lands immediately before A.
        await sut.reorder(draggedID: c.id, onto: a.id)

        XCTAssertEqual(mockReorder.orderedIDs, [c.id, a.id, b.id])
    }

    func testReorder_reloadsRegistryAfterMutation() async {
        let work = CategoryResponse(id: UUID(), name: "Work", sortIndex: 0)
        let a = ItemFixtures.make(name: "A", categoryID: work.id)
        let b = ItemFixtures.make(name: "B", categoryID: work.id)
        mockCategories.result = [work]
        mockFetch.result = [a, b]
        await sut.load()
        sut.selection = .category(work.id)
        let before = mockFetch.callCount

        await sut.reorder(draggedID: b.id, onto: a.id)

        XCTAssertEqual(mockFetch.callCount, before + 1)
    }

    func testReorder_optimisticallyReordersVisibleItems() async {
        let work = CategoryResponse(id: UUID(), name: "Work", sortIndex: 0)
        let a = ItemFixtures.make(name: "A", categoryID: work.id)
        let b = ItemFixtures.make(name: "B", categoryID: work.id)
        mockCategories.result = [work]
        mockFetch.result = [a, b]
        await sut.load()
        sut.selection = .category(work.id)
        // The post-mutation reload re-reads the store; mirror the persisted new
        // order so the reconcile keeps (not reverts) the optimistic reorder.
        mockFetch.result = [b, a]

        await sut.reorder(draggedID: b.id, onto: a.id)

        XCTAssertEqual(sut.visibleItems.map(\.name), ["B", "A"])
    }

    func testReorder_ignoresDraggedEntryFromAnotherCategory() async {
        let work = CategoryResponse(id: UUID(), name: "Work", sortIndex: 0)
        let play = CategoryResponse(id: UUID(), name: "Play", sortIndex: 1)
        let a = ItemFixtures.make(name: "A", categoryID: work.id)
        let other = ItemFixtures.make(name: "Other", categoryID: play.id)
        mockCategories.result = [work, play]
        mockFetch.result = [a, other]
        await sut.load()
        sut.selection = .category(work.id)

        // Dragged id isn't in the Work category — reorder is a no-op (that path is
        // a cross-category move, handled by the sidebar drop, not this method).
        await sut.reorder(draggedID: other.id, onto: a.id)

        XCTAssertNil(mockReorder.orderedIDs)
    }

    // MARK: - moveEntry(_:to:)

    func testMoveEntry_callsUseCaseWithEntryAndTargetCategory() async {
        let work = CategoryResponse(id: UUID(), name: "Work", sortIndex: 0)
        let home = CategoryResponse(id: UUID(), name: "Home", sortIndex: 1)
        let item = ItemFixtures.make(name: "A", categoryID: work.id)
        mockCategories.result = [work, home]
        mockFetch.result = [item]
        await sut.load()

        await sut.moveEntry(item.id, to: home.id)

        XCTAssertEqual(mockMove.receivedRequest?.entryID, item.id)
        XCTAssertEqual(mockMove.receivedRequest?.categoryID, home.id)
    }

    func testMoveEntry_optimisticallyRetagsItemLocally() async {
        let work = CategoryResponse(id: UUID(), name: "Work", sortIndex: 0)
        let home = CategoryResponse(id: UUID(), name: "Home", sortIndex: 1)
        let item = ItemFixtures.make(name: "A", categoryID: work.id)
        mockCategories.result = [work, home]
        mockFetch.result = [item]
        await sut.load()
        sut.selection = .category(work.id)
        // The post-mutation reload re-reads the store; mirror the persisted move
        // (item retagged to Home) so the reconcile keeps the optimistic retag.
        mockFetch.result = [ItemFixtures.make(id: item.id, name: "A", categoryID: home.id)]

        await sut.moveEntry(item.id, to: home.id)

        // It leaves the source category's visible list immediately.
        XCTAssertTrue(sut.visibleItems.isEmpty)
    }

    func testMoveEntry_sameCategoryIsNoOp() async {
        let work = CategoryResponse(id: UUID(), name: "Work", sortIndex: 0)
        let item = ItemFixtures.make(name: "A", categoryID: work.id)
        mockCategories.result = [work]
        mockFetch.result = [item]
        await sut.load()

        await sut.moveEntry(item.id, to: work.id)

        XCTAssertEqual(mockMove.callCount, 0)
    }

    func testMoveEntry_reloadsRegistryAfterMutation() async {
        let work = CategoryResponse(id: UUID(), name: "Work", sortIndex: 0)
        let home = CategoryResponse(id: UUID(), name: "Home", sortIndex: 1)
        let item = ItemFixtures.make(name: "A", categoryID: work.id)
        mockCategories.result = [work, home]
        mockFetch.result = [item]
        await sut.load()
        let before = mockFetch.callCount

        await sut.moveEntry(item.id, to: home.id)

        XCTAssertEqual(mockFetch.callCount, before + 1)
    }

    // MARK: - beginAdd()

    func testBeginAdd_pushesAddRoute() {
        sut.beginAdd()

        XCTAssertEqual(sut.formPath, [.add])
    }

    func testBeginAdd_replacesAnExistingRoute() {
        sut.beginEdit(ItemFixtures.make())

        sut.beginAdd()

        XCTAssertEqual(sut.formPath, [.add])
    }

    // MARK: - beginEdit(_:)

    func testBeginEdit_pushesEditRouteForItemID() {
        let item = ItemFixtures.make(name: "Edit me")

        sut.beginEdit(item)

        XCTAssertEqual(sut.formPath, [.edit(item.id)])
    }

    func testBeginEdit_presentsForm() {
        sut.beginEdit(ItemFixtures.make())

        XCTAssertEqual(sut.formPath.count, 1)
    }

    // MARK: - categories

    func testCommitAddCategory_callsRegisterWithTrimmedName() async {
        sut.newCategoryName = "  Work  "

        await sut.commitAddCategory()

        XCTAssertEqual(mockRegisterCategory.callCount, 1)
        XCTAssertEqual(mockRegisterCategory.receivedName, "Work")
    }

    func testCommitAddCategory_selectsNewCategoryAndClearsEditor() async {
        let created = CategoryResponse(id: UUID(), name: "Work", sortIndex: 1)
        mockRegisterCategory.result = created
        sut.newCategoryName = "Work"

        await sut.commitAddCategory()

        XCTAssertEqual(sut.selectedCategoryID, created.id)
        XCTAssertFalse(sut.isAddingCategory)
        XCTAssertEqual(sut.newCategoryName, "")
    }

    func testCommitAddCategory_ignoresBlankName() async {
        sut.newCategoryName = "   "

        await sut.commitAddCategory()

        XCTAssertEqual(mockRegisterCategory.callCount, 0)
    }

    func testRemoveCategory_callsDeleteWithCategoryID() async {
        let category = CategoryResponse(id: UUID(), name: "Work", sortIndex: 1)

        await sut.removeCategory(category)

        XCTAssertEqual(mockDeleteCategory.callCount, 1)
        XCTAssertEqual(mockDeleteCategory.deletedID, category.id)
    }

    func testRemoveCategory_reloadsRegistryAfterMutation() async {
        let before = mockFetch.callCount

        await sut.removeCategory(CategoryResponse(id: UUID(), name: "X", sortIndex: 1))

        XCTAssertEqual(mockFetch.callCount, before + 1)
    }

    // MARK: - toggleCategoryVisibility(_:)

    func testToggleCategoryVisibility_visibleCategory_requestsHide() async {
        let category = CategoryResponse(id: UUID(), name: "Work", sortIndex: 0, isHiddenFromMenuBar: false)

        await sut.toggleCategoryVisibility(category)

        XCTAssertEqual(mockEditCategory.received?.isHiddenFromMenuBar, true)
    }

    func testToggleCategoryVisibility_hiddenCategory_requestsShow() async {
        let category = CategoryResponse(id: UUID(), name: "Work", sortIndex: 0, isHiddenFromMenuBar: true)

        await sut.toggleCategoryVisibility(category)

        XCTAssertEqual(mockEditCategory.received?.isHiddenFromMenuBar, false)
    }

    func testToggleCategoryVisibility_keepsCurrentNameAndID() async {
        let category = CategoryResponse(id: UUID(), name: "Work", sortIndex: 0, isHiddenFromMenuBar: false)

        await sut.toggleCategoryVisibility(category)

        XCTAssertEqual(mockEditCategory.received?.id, category.id)
        XCTAssertEqual(mockEditCategory.received?.name, "Work")
    }

    func testToggleCategoryVisibility_reloadsRegistryAfterMutation() async {
        let before = mockFetch.callCount

        await sut.toggleCategoryVisibility(CategoryResponse(id: UUID(), name: "X", sortIndex: 0))

        XCTAssertEqual(mockFetch.callCount, before + 1)
    }

    // MARK: - moveSelectedCategory(by:)

    func testMoveSelectedCategoryDown_callsReorderWithSwappedOrder() async {
        let a = CategoryResponse(id: UUID(), name: "A", sortIndex: 0)
        let b = CategoryResponse(id: UUID(), name: "B", sortIndex: 1)
        let c = CategoryResponse(id: UUID(), name: "C", sortIndex: 2)
        mockCategories.result = [a, b, c]
        await sut.load()
        sut.selection = .category(a.id)

        await sut.moveSelectedCategory(by: 1)

        XCTAssertEqual(mockReorderCategories.orderedIDs, [b.id, a.id, c.id])
    }

    func testMoveSelectedCategoryUp_optimisticallyReordersLocally() async {
        let a = CategoryResponse(id: UUID(), name: "A", sortIndex: 0)
        let b = CategoryResponse(id: UUID(), name: "B", sortIndex: 1)
        mockCategories.result = [a, b]
        await sut.load()
        sut.selection = .category(b.id)
        // The post-mutation reload re-reads the store; mirror the persisted swap so
        // the reconcile keeps (not reverts) the optimistic reorder.
        mockCategories.result = [
            CategoryResponse(id: b.id, name: "B", sortIndex: 0),
            CategoryResponse(id: a.id, name: "A", sortIndex: 1)
        ]

        await sut.moveSelectedCategory(by: -1)

        XCTAssertEqual(sut.categories.map(\.name), ["B", "A"])
    }

    func testMoveSelectedCategory_reloadsRegistryAfterMutation() async {
        let a = CategoryResponse(id: UUID(), name: "A", sortIndex: 0)
        let b = CategoryResponse(id: UUID(), name: "B", sortIndex: 1)
        mockCategories.result = [a, b]
        await sut.load()
        sut.selection = .category(a.id)
        let before = mockFetch.callCount

        await sut.moveSelectedCategory(by: 1)

        XCTAssertEqual(mockFetch.callCount, before + 1)
    }

    func testMoveSelectedCategory_atTopMovingUpIsNoOp() async {
        let a = CategoryResponse(id: UUID(), name: "A", sortIndex: 0)
        let b = CategoryResponse(id: UUID(), name: "B", sortIndex: 1)
        mockCategories.result = [a, b]
        await sut.load()
        sut.selection = .category(a.id)

        await sut.moveSelectedCategory(by: -1)

        XCTAssertEqual(mockReorderCategories.callCount, 0)
    }

    func testCanMoveSelectedCategoryUp_falseWhenFirstSelected() async {
        let a = CategoryResponse(id: UUID(), name: "A", sortIndex: 0)
        let b = CategoryResponse(id: UUID(), name: "B", sortIndex: 1)
        mockCategories.result = [a, b]
        await sut.load()
        sut.selection = .category(a.id)

        XCTAssertFalse(sut.canMoveSelectedCategoryUp)
    }

    func testCanMoveSelectedCategoryDown_falseWhenLastSelected() async {
        let a = CategoryResponse(id: UUID(), name: "A", sortIndex: 0)
        let b = CategoryResponse(id: UUID(), name: "B", sortIndex: 1)
        mockCategories.result = [a, b]
        await sut.load()
        sut.selection = .category(b.id)

        XCTAssertFalse(sut.canMoveSelectedCategoryDown)
    }

    func testCanMoveSelectedCategoryUp_falseOnTerminalAppPane() async {
        mockCategories.result = [CategoryResponse(id: UUID(), name: "A", sortIndex: 0)]
        await sut.load()
        sut.selection = .terminalApp

        XCTAssertFalse(sut.canMoveSelectedCategoryUp)
    }
}
