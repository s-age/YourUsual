import XCTest
@testable import YourUsual

// MARK: - Mock

final class MockSavedEntryRepository: SavedEntryRepositoryProtocol, @unchecked Sendable {
    var items: [SavedEntry] = []
    var loadError: Error?

    var listAllCallCount = 0

    func listAll() throws -> [SavedEntry] {
        listAllCallCount += 1
        if let loadError { throw loadError }
        return items
    }
}

final class SavedEntryServiceTests: XCTestCase {
    private var sut: SavedEntryService!
    private var repository: MockSavedEntryRepository!

    override func setUp() {
        super.setUp()
        repository = MockSavedEntryRepository()
        sut = SavedEntryService(repository: repository)
    }

    override func tearDown() {
        sut = nil
        repository = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func browseKind(_ path: String = "/tmp/file") -> EntryKind {
        .browse(BrowseEntry(url: URL(fileURLWithPath: path), app: .default))
    }

    private func browseEntry(_ name: String, path: String, sortIndex: Int) -> SavedEntry {
        SavedEntry(name: name, kind: browseKind(path), sortIndex: sortIndex)
    }

    // MARK: - healingRecovered

    func test_healingRecovered_noRecoveredEntries_returnsNil() {
        let intact = [browseEntry("Notes", path: "/tmp/notes", sortIndex: 0)]
        XCTAssertNil(sut.healingRecovered(intact))
    }

    func test_healingRecovered_someRecovered_returnsWholeCollection() {
        let recovered = SavedEntry(
            name: "Broken", kind: browseKind(), sortIndex: 0, isRecovered: true
        )
        let intact = browseEntry("Notes", path: "/tmp/notes", sortIndex: 1)
        let result = sut.healingRecovered([recovered, intact])
        XCTAssertEqual(result?.items.count, 2)
    }

    func test_healingRecovered_returnsHealedCountOfPlaceholders() {
        let recovered1 = SavedEntry(name: "Broken1", kind: browseKind(), sortIndex: 0, isRecovered: true)
        let recovered2 = SavedEntry(name: "Broken2", kind: browseKind(), sortIndex: 1, isRecovered: true)
        let intact = browseEntry("Notes", path: "/tmp/notes", sortIndex: 2)
        let result = sut.healingRecovered([recovered1, recovered2, intact])
        XCTAssertEqual(result?.healedCount, 2)
    }

    func test_healingRecovered_clearsTheRecoveredFlagSoTheWriteOverwrites() {
        // The flag must be cleared so the write path persists (converts) the placeholder
        // rather than preserving the undecodable original.
        let recovered = SavedEntry(
            name: "Broken", kind: browseKind(), sortIndex: 0, isRecovered: true
        )
        let result = sut.healingRecovered([recovered])
        XCTAssertEqual(result?.items.first?.isRecovered, false)
    }

    func test_healingRecovered_leavesIntactEntriesUnchanged() {
        let intact = browseEntry("Notes", path: "/tmp/notes", sortIndex: 0)
        let recovered = SavedEntry(name: "Broken", kind: browseKind(), sortIndex: 1, isRecovered: true)
        let result = sut.healingRecovered([intact, recovered])
        XCTAssertEqual(result?.items.first, intact)
    }

    func test_healingRecovered_emptyCollection_returnsNil() {
        XCTAssertNil(sut.healingRecovered([]))
    }

    // MARK: - listAll

    func test_listAll_delegatesToRepository() async throws {
        let item = browseEntry("Notes", path: "/tmp/notes", sortIndex: 0)
        repository.items = [item]
        let result = try await sut.listAll()
        XCTAssertEqual(result, [item])
    }

    func test_listAll_callsRepositoryOnce() async throws {
        _ = try await sut.listAll()
        XCTAssertEqual(repository.listAllCallCount, 1)
    }

    // MARK: - registering: sortIndex assignment

    func test_registering_firstItem_assignsSortIndexZero() {
        let result = sut.registering([], name: "First", kind: browseKind("/tmp/first"), categoryID: nil)
        XCTAssertEqual(result.registered.sortIndex, 0)
    }

    func test_registering_appendsWithMaxSortIndexPlusOne() {
        let current = [
            browseEntry("a", path: "/a", sortIndex: 3),
            browseEntry("b", path: "/b", sortIndex: 7),
        ]
        let result = sut.registering(current, name: "c", kind: browseKind("/c"), categoryID: nil)
        XCTAssertEqual(result.registered.sortIndex, 8)
    }

    func test_registering_returnsCollectionWithNewItemAppended() {
        let result = sut.registering([], name: "First", kind: browseKind("/tmp/first"), categoryID: nil)
        XCTAssertEqual(result.items, [result.registered])
    }

    func test_registering_trimsName() {
        let result = sut.registering([], name: "  foo  ", kind: browseKind("/tmp/foo"), categoryID: nil)
        XCTAssertEqual(result.registered.name, "foo")
    }

    // MARK: - registering: category assignment

    func test_registering_withCategoryID_assignsThatCategory() {
        let target = UUID()
        let result = sut.registering([], name: "x", kind: browseKind("/x"), categoryID: target)
        XCTAssertEqual(result.registered.categoryID, target)
    }

    func test_registering_nilCategoryID_fallsBackToDefault() {
        let result = sut.registering([], name: "x", kind: browseKind("/x"), categoryID: nil)
        XCTAssertEqual(result.registered.categoryID, EntryCategory.defaultID)
    }

    // MARK: - editing: not found

    func test_editing_unknownId_throwsItemNotFound() {
        XCTAssertThrowsError(
            try sut.editing([], id: UUID(), edit: SavedEntryEdit(name: "ghost", kind: browseKind("/ghost"), isHiddenFromMenuBar: false))
        ) { error in
            guard case OperationError.itemNotFound = error else {
                return XCTFail("Expected .itemNotFound, got \(error)")
            }
        }
    }

    func test_editing_existingId_preservesId() throws {
        let item = browseEntry("orig", path: "/orig", sortIndex: 5)
        let result = try sut.editing(
            [item], id: item.id, edit: SavedEntryEdit(name: "renamed", kind: browseKind("/new"), isHiddenFromMenuBar: false)
        )
        XCTAssertEqual(result.edited.id, item.id)
    }

    func test_editing_existingId_preservesSortIndex() throws {
        let item = browseEntry("orig", path: "/orig", sortIndex: 5)
        let result = try sut.editing(
            [item], id: item.id, edit: SavedEntryEdit(name: "renamed", kind: browseKind("/new"), isHiddenFromMenuBar: false)
        )
        XCTAssertEqual(result.edited.sortIndex, 5)
    }

    func test_editing_existingId_appliesName() throws {
        let item = browseEntry("orig", path: "/orig", sortIndex: 5)
        let result = try sut.editing(
            [item], id: item.id, edit: SavedEntryEdit(name: "renamed", kind: browseKind("/new"), isHiddenFromMenuBar: false)
        )
        XCTAssertEqual(result.edited.name, "renamed")
    }

    func test_editing_existingId_appliesKind() throws {
        let item = browseEntry("orig", path: "/orig", sortIndex: 5)
        let result = try sut.editing(
            [item], id: item.id, edit: SavedEntryEdit(name: "renamed", kind: browseKind("/new"), isHiddenFromMenuBar: false)
        )
        XCTAssertEqual(result.edited.kind, browseKind("/new"))
    }

    func test_editing_existingId_appliesHiddenFromMenuBar() throws {
        let item = browseEntry("orig", path: "/orig", sortIndex: 5)
        let result = try sut.editing(
            [item], id: item.id,
            edit: SavedEntryEdit(name: "renamed", kind: browseKind("/new"), isHiddenFromMenuBar: true)
        )
        XCTAssertTrue(result.edited.isHiddenFromMenuBar)
    }

    func test_editing_trimsName() throws {
        let item = browseEntry("orig", path: "/orig", sortIndex: 5)
        let result = try sut.editing(
            [item], id: item.id, edit: SavedEntryEdit(name: "  foo  ", kind: browseKind("/new"), isHiddenFromMenuBar: false)
        )
        XCTAssertEqual(result.edited.name, "foo")
    }

    func test_editing_recoveredEntry_clearsRecoveredFlag() throws {
        // Re-entering a recovered placeholder makes it a real entry, so the flag must
        // clear — that's what lets the write path overwrite the preserved original.
        let recovered = SavedEntry(
            name: "broken", kind: browseKind("/orig"), sortIndex: 0, isRecovered: true
        )
        let result = try sut.editing(
            [recovered], id: recovered.id,
            edit: SavedEntryEdit(name: "fixed", kind: browseKind("/new"), isHiddenFromMenuBar: false)
        )
        XCTAssertFalse(result.edited.isRecovered)
    }

    // MARK: - deleting: not found

    func test_deleting_unknownId_throwsItemNotFound() {
        XCTAssertThrowsError(try sut.deleting([], id: UUID())) { error in
            guard case OperationError.itemNotFound = error else {
                return XCTFail("Expected .itemNotFound, got \(error)")
            }
        }
    }

    // MARK: - deleting: success

    func test_deleting_existingId_removesItem() throws {
        let item = browseEntry("doomed", path: "/doomed", sortIndex: 0)
        let result = try sut.deleting([item], id: item.id)
        XCTAssertEqual(result, [])
    }

    // MARK: - reordering

    func test_reordering_reassignsSortIndexToMatchGivenOrder() throws {
        let a = browseEntry("a", path: "/a", sortIndex: 0)
        let b = browseEntry("b", path: "/b", sortIndex: 1)
        let c = browseEntry("c", path: "/c", sortIndex: 2)

        let result = try XCTUnwrap(sut.reordering([a, b, c], orderedIDs: [c.id, a.id, b.id]))

        let index = Dictionary(uniqueKeysWithValues: result.map { ($0.name, $0.sortIndex) })
        // Original ascending slots 0,1,2 reused in the new order c,a,b.
        XCTAssertEqual(index["c"], 0)
        XCTAssertEqual(index["a"], 1)
        XCTAssertEqual(index["b"], 2)
    }

    func test_reordering_leavesOtherCategorySlotsUntouched() throws {
        let catA = UUID()
        let catB = UUID()
        let a1 = SavedEntry(name: "a1", kind: browseKind("/a1"), sortIndex: 0, categoryID: catA)
        let b1 = SavedEntry(name: "b1", kind: browseKind("/b1"), sortIndex: 1, categoryID: catB)
        let a2 = SavedEntry(name: "a2", kind: browseKind("/a2"), sortIndex: 2, categoryID: catA)

        // Reorder only category A's entries (slots 0 and 2): a2 before a1.
        let result = try XCTUnwrap(sut.reordering([a1, b1, a2], orderedIDs: [a2.id, a1.id]))

        let index = Dictionary(uniqueKeysWithValues: result.map { ($0.name, $0.sortIndex) })
        XCTAssertEqual(index["a2"], 0)
        XCTAssertEqual(index["a1"], 2)
        XCTAssertEqual(index["b1"], 1)  // other category's slot untouched
    }

    func test_reordering_singleElement_returnsNil() {
        let only = browseEntry("only", path: "/o", sortIndex: 7)
        XCTAssertNil(sut.reordering([only], orderedIDs: [only.id]))
    }

    func test_reordering_excludesRecoveredPlaceholderFromSlotPool() throws {
        // `a` is an undecodable recovery placeholder; its slot is never persisted (the
        // write path preserves its intact row), so reassigning that slot to a sibling
        // would leave two entries sharing one slot on reload. It must be excluded.
        let a = SavedEntry(name: "a", kind: browseKind("/a"), sortIndex: 0, isRecovered: true)
        let b = browseEntry("b", path: "/b", sortIndex: 1)
        let c = browseEntry("c", path: "/c", sortIndex: 2)

        let result = try XCTUnwrap(sut.reordering([a, b, c], orderedIDs: [c.id, a.id, b.id]))

        let index = Dictionary(uniqueKeysWithValues: result.map { ($0.name, $0.sortIndex) })
        // Placeholder keeps its slot; the real entries renumber among their own slots (1,2).
        XCTAssertEqual(index["a"], 0)
        XCTAssertEqual(index["c"], 1)
        XCTAssertEqual(index["b"], 2)
    }

    func test_reordering_excludingPlaceholderLeavesOneReal_returnsNil() {
        // Excluding the placeholder drops the reorderable set to one entry → no-op.
        let a = SavedEntry(name: "a", kind: browseKind("/a"), sortIndex: 0, isRecovered: true)
        let b = browseEntry("b", path: "/b", sortIndex: 1)
        XCTAssertNil(sut.reordering([a, b], orderedIDs: [b.id, a.id]))
    }

    // MARK: - moving

    func test_moving_changesCategoryOfEntry() throws {
        let catA = UUID()
        let catB = UUID()
        let item = SavedEntry(name: "x", kind: browseKind("/x"), sortIndex: 0, categoryID: catA)

        let result = try XCTUnwrap(
            sut.moving([item], id: item.id, toCategory: catB, knownCategoryIDs: [catA, catB])
        )

        XCTAssertEqual(result.first?.categoryID, catB)
    }

    func test_moving_appendsAtGlobalMaxSortIndexPlusOne() throws {
        let catA = UUID()
        let catB = UUID()
        let moved = SavedEntry(name: "moved", kind: browseKind("/m"), sortIndex: 0, categoryID: catA)
        let other = SavedEntry(name: "other", kind: browseKind("/o"), sortIndex: 5, categoryID: catB)

        let result = try XCTUnwrap(
            sut.moving([moved, other], id: moved.id, toCategory: catB, knownCategoryIDs: [catA, catB])
        )

        let saved = Dictionary(uniqueKeysWithValues: result.map { ($0.name, $0.sortIndex) })
        XCTAssertEqual(saved["moved"], 6)  // max(0,5) + 1
    }

    func test_moving_unknownId_throwsItemNotFound() {
        XCTAssertThrowsError(
            try sut.moving([], id: UUID(), toCategory: UUID(), knownCategoryIDs: [])
        ) { error in
            guard case OperationError.itemNotFound = error else {
                return XCTFail("Expected .itemNotFound, got \(error)")
            }
        }
    }

    func test_moving_unknownTargetCategory_throwsCategoryNotFound() {
        let catA = UUID()
        let missingCat = UUID()
        let item = SavedEntry(name: "x", kind: browseKind("/x"), sortIndex: 0, categoryID: catA)
        XCTAssertThrowsError(
            try sut.moving([item], id: item.id, toCategory: missingCat, knownCategoryIDs: [catA])
        ) { error in
            guard case OperationError.categoryNotFound(let id) = error else {
                return XCTFail("Expected .categoryNotFound, got \(error)")
            }
            XCTAssertEqual(id, missingCat)
        }
    }

    func test_moving_sameCategory_returnsNil() throws {
        let cat = UUID()
        let item = SavedEntry(name: "x", kind: browseKind("/x"), sortIndex: 0, categoryID: cat)
        XCTAssertNil(try sut.moving([item], id: item.id, toCategory: cat, knownCategoryIDs: [cat]))
    }

    // MARK: - slider: menu-bar visibility forced by Domain rule

    private func sliderKind(current: Double = 50) -> EntryKind {
        .slider(SliderEntry(commandLine: "echo <VALUE>", minValue: 0, maxValue: 100, step: 1, currentValue: current))
    }

    func test_registering_sliderKind_forcesHiddenFromMenuBar() {
        let result = sut.registering([], name: "Volume", kind: sliderKind(), categoryID: nil)
        XCTAssertTrue(result.registered.isHiddenFromMenuBar)
    }

    func test_registering_browseKind_staysVisible_regression() {
        let result = sut.registering([], name: "Notes", kind: browseKind("/n"), categoryID: nil)
        XCTAssertFalse(result.registered.isHiddenFromMenuBar)
    }

    func test_editing_sliderKind_forcesHiddenEvenWhenEditSaysVisible() throws {
        let item = SavedEntry(name: "Volume", kind: sliderKind(), sortIndex: 0, isHiddenFromMenuBar: true)
        let result = try sut.editing(
            [item], id: item.id,
            edit: SavedEntryEdit(name: "Volume", kind: sliderKind(), isHiddenFromMenuBar: false)
        )
        XCTAssertTrue(result.edited.isHiddenFromMenuBar)
    }

    // MARK: - editingSliderValue

    func test_editingSliderValue_updatesOnlyTargetSliderValue() {
        let target = SavedEntry(name: "Volume", kind: sliderKind(current: 50), sortIndex: 0)
        let result = sut.editingSliderValue([target], id: target.id, value: 80)
        guard case .slider(let slider) = result.first?.kind else {
            return XCTFail("Expected the entry to remain a slider")
        }
        XCTAssertEqual(slider.currentValue, 80)
    }

    func test_editingSliderValue_clampsToBounds() {
        let target = SavedEntry(name: "Volume", kind: sliderKind(current: 50), sortIndex: 0)
        let result = sut.editingSliderValue([target], id: target.id, value: 999)
        guard case .slider(let slider) = result.first?.kind else {
            return XCTFail("Expected the entry to remain a slider")
        }
        XCTAssertEqual(slider.currentValue, 100)  // maxValue
    }

    func test_editingSliderValue_leavesOtherEntriesUntouched() {
        let other = browseEntry("Notes", path: "/n", sortIndex: 0)
        let target = SavedEntry(name: "Volume", kind: sliderKind(current: 50), sortIndex: 1)
        let result = sut.editingSliderValue([other, target], id: target.id, value: 80)
        XCTAssertEqual(result.first, other)
    }

    func test_editingSliderValue_nonSliderMatch_isNoOp() {
        let browse = browseEntry("Notes", path: "/n", sortIndex: 0)
        let result = sut.editingSliderValue([browse], id: browse.id, value: 80)
        XCTAssertEqual(result, [browse])
    }

    func test_editingSliderValue_unknownId_isNoOp() {
        let target = SavedEntry(name: "Volume", kind: sliderKind(current: 50), sortIndex: 0)
        let result = sut.editingSliderValue([target], id: UUID(), value: 80)
        XCTAssertEqual(result, [target])
    }
}
