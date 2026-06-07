import XCTest
import SwiftData
@testable import YourUsual

/// Exercises the REAL `RegistryDatabase` for the category→entry ownership link:
/// the `.cascade` delete rule removes a category's entries in one transaction.
/// Also covers category reconcile delete-missing. Mutations drive
/// `tx.replaceAllCategories` / `tx.replaceAllEntries` through the UseCase-owned
/// transaction boundary; reads use `SavedEntryRepository` / `CategoryRepository`.
final class RegistryDatabaseCategoryCascadeTests: XCTestCase {
    private var db: RegistryDatabase!
    private var sut: RegistryDatabaseGateway!
    private var entryRepo: SavedEntryRepository!
    private var categoryRepo: CategoryRepository!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: EntryModel.self, CommandRunModel.self, CategoryModel.self,
            BrowseEntryModel.self, CommandEntryModel.self, AppleScriptEntryModel.self,
            configurations: config
        )
        db = RegistryDatabase(modelContainer: container)
        sut = RegistryDatabaseGateway(runner: db)
        entryRepo = SavedEntryRepository(store: db, logger: MockDiagnosticsLogger())
        categoryRepo = CategoryRepository(store: db)
    }

    override func tearDown() {
        sut = nil
        db = nil
        entryRepo = nil
        categoryRepo = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func replaceCategories(_ cats: [EntryCategory]) async throws {
        try await sut.transaction { tx in try tx.replaceAllCategories(cats) }
    }

    private func replaceEntries(_ items: [SavedEntry]) async throws {
        try await sut.transaction { tx in try tx.replaceAllEntries(items) }
    }

    private func browseEntry(named name: String, in categoryID: UUID) -> SavedEntry {
        SavedEntry(
            name: name,
            kind: .browse(BrowseEntry(url: URL(fileURLWithPath: "/tmp/\(name)"), app: .default)),
            sortIndex: 0,
            categoryID: categoryID
        )
    }

    // MARK: - Ordering (the store sorts by sortIndex; the repository trusts that order)

    func testListAll_returnsCategoriesSortedBySortIndex() async throws {
        try await replaceCategories([
            EntryCategory(id: UUID(), name: "two", sortIndex: 2),
            EntryCategory(id: UUID(), name: "zero", sortIndex: 0),
            EntryCategory(id: UUID(), name: "one", sortIndex: 1),
        ])
        let loaded = try await categoryRepo.listAll()
        XCTAssertEqual(loaded.map(\.sortIndex), [0, 1, 2])
    }

    // MARK: - Menu-bar visibility round-trip (full store path: mapper + Model↔DTO)

    func testRoundTrip_category_isHiddenFromMenuBar_true_persists() async throws {
        let id = UUID()
        try await replaceCategories([
            EntryCategory(id: id, name: "Work", sortIndex: 0, isHiddenFromMenuBar: true)
        ])
        let loaded = try await categoryRepo.listAll().first
        XCTAssertEqual(loaded?.isHiddenFromMenuBar, true)
    }

    func testRoundTrip_category_isHiddenFromMenuBar_false_persists() async throws {
        let id = UUID()
        try await replaceCategories([
            EntryCategory(id: id, name: "Work", sortIndex: 0, isHiddenFromMenuBar: false)
        ])
        let loaded = try await categoryRepo.listAll().first
        XCTAssertEqual(loaded?.isHiddenFromMenuBar, false)
    }

    // The reconcile edit path (apply to an existing model) must update the flag too.
    func testEdit_category_isHiddenFromMenuBar_visibleToHidden_persists() async throws {
        let id = UUID()
        try await replaceCategories([
            EntryCategory(id: id, name: "Work", sortIndex: 0, isHiddenFromMenuBar: false)
        ])
        try await replaceCategories([
            EntryCategory(id: id, name: "Work", sortIndex: 0, isHiddenFromMenuBar: true)
        ])
        let loaded = try await categoryRepo.listAll().first
        XCTAssertEqual(loaded?.isHiddenFromMenuBar, true)
    }

    // MARK: - Cascade

    func testCascade_deletingCategory_removesItsEntries() async throws {
        let catID = UUID()
        try await replaceCategories([EntryCategory(id: catID, name: "Work", sortIndex: 0)])
        try await replaceEntries([browseEntry(named: "a", in: catID)])
        // Remove the category via whole-collection reconcile.
        try await replaceCategories([])
        let remaining = try await entryRepo.listAll()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testCascade_deletingCategory_leavesEntriesOfOtherCategory() async throws {
        let doomed = UUID()
        let kept = UUID()
        try await replaceCategories([
            EntryCategory(id: doomed, name: "Doomed", sortIndex: 0),
            EntryCategory(id: kept, name: "Kept", sortIndex: 1)
        ])
        try await replaceEntries([
            browseEntry(named: "a", in: doomed),
            browseEntry(named: "b", in: kept)
        ])
        try await replaceCategories([EntryCategory(id: kept, name: "Kept", sortIndex: 0)])
        let remaining = try await entryRepo.listAll()
        XCTAssertEqual(remaining.map(\.name), ["b"])
    }

    func testCascade_deletingCategory_atomicWithinSinglePerform() async throws {
        let catID = UUID()
        try await replaceCategories([EntryCategory(id: catID, name: "Work", sortIndex: 0)])
        try await replaceEntries([
            browseEntry(named: "x", in: catID),
            browseEntry(named: "y", in: catID)
        ])
        // Both entries and the category disappear atomically in one perform.
        try await replaceCategories([])
        let categories = try await categoryRepo.listAll()
        let entries = try await entryRepo.listAll()
        XCTAssertTrue(categories.isEmpty)
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - Category reconcile delete-missing

    func testCategoryReconcile_absentCategory_isRemoved() async throws {
        let kept = UUID()
        let dropped = UUID()
        try await replaceCategories([
            EntryCategory(id: kept, name: "Kept", sortIndex: 0),
            EntryCategory(id: dropped, name: "Dropped", sortIndex: 1)
        ])
        try await replaceCategories([EntryCategory(id: kept, name: "Kept", sortIndex: 0)])
        let ids = try await categoryRepo.listAll().map(\.id)
        XCTAssertFalse(ids.contains(dropped))
    }

    func testCategoryReconcile_absentCategory_doesNotRemoveKeptCategory() async throws {
        let kept = UUID()
        let dropped = UUID()
        try await replaceCategories([
            EntryCategory(id: kept, name: "Kept", sortIndex: 0),
            EntryCategory(id: dropped, name: "Dropped", sortIndex: 1)
        ])
        try await replaceCategories([EntryCategory(id: kept, name: "Kept", sortIndex: 0)])
        let ids = try await categoryRepo.listAll().map(\.id)
        XCTAssertTrue(ids.contains(kept))
    }
}
