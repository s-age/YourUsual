import XCTest
import SwiftData
@testable import YourUsual

/// Verifies the V1→V2 registry migration that the Launcher Pad introduced
/// (`RegistrySchemaV1` → `RegistrySchemaV2`, the `.lightweight` stage in
/// `RegistryMigrationPlan` that adds the `PadLayoutModel` / `PadCellModel` tables).
///
/// Uses a real **on-disk** store rather than `isStoredInMemoryOnly` because the
/// migration only runs when SwiftData reopens a store whose recorded version is older
/// than the schema it is asked for — an in-memory store has nothing to migrate from.
/// The flow mirrors a real launch after an app update: a store created by the old
/// binary (V1, holding the user's entries) is reopened by the new binary (V2).
final class MigratePadSchemaTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "pad-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appending(path: "registry.store", directoryHint: .notDirectory)
    }

    override func tearDownWithError() throws {
        let dir = storeURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
        storeURL = nil
    }

    /// Creates a V1 store at `storeURL` containing a single entry, then releases it so
    /// the file is closed before the V2 reopen. Returns the seeded entry's id.
    private func seedV1Store() throws -> UUID {
        let schema = Schema(versionedSchema: RegistrySchemaV1.self)
        let config = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        let entryID = UUID()
        context.insert(EntryModel(id: entryID, name: "Existing", sortIndex: 0, entryType: "command"))
        try context.save()
        return entryID
    }

    /// Reopens `storeURL` through the real migration plan, exactly as `RegistryStoreFactory` does.
    private func openV2Store() throws -> ModelContainer {
        let schema = Schema(versionedSchema: RegistrySchemaV2.self)
        let config = ModelConfiguration(url: storeURL)
        return try ModelContainer(for: schema,
                                  migrationPlan: RegistryMigrationPlan.self,
                                  configurations: config)
    }

    // MARK: - Migration preserves existing data

    func test_migrateV1ToV2_opensWithoutThrowing() throws {
        _ = try seedV1Store()
        XCTAssertNoThrow(try openV2Store())
    }

    func test_migrateV1ToV2_preservesExistingEntries() throws {
        _ = try seedV1Store()
        let context = ModelContext(try openV2Store())
        let entries = try context.fetch(FetchDescriptor<EntryModel>())
        XCTAssertEqual(entries.count, 1)
    }

    func test_migrateV1ToV2_preservesEntryIdentity() throws {
        let seededID = try seedV1Store()
        let context = ModelContext(try openV2Store())
        let entries = try context.fetch(FetchDescriptor<EntryModel>())
        XCTAssertEqual(entries.first?.id, seededID)
    }

    // MARK: - New pad tables are usable after migration

    func test_migrateV1ToV2_padLayoutTableIsWritable() throws {
        _ = try seedV1Store()
        let context = ModelContext(try openV2Store())
        context.insert(PadLayoutModel(id: UUID(), name: "Pad", columns: 4, rows: 4, sortIndex: 0))
        try context.save()
        let layouts = try context.fetch(FetchDescriptor<PadLayoutModel>())
        XCTAssertEqual(layouts.count, 1)
    }

    func test_migrateV1ToV2_padTablesStartEmpty() throws {
        _ = try seedV1Store()
        let context = ModelContext(try openV2Store())
        let layouts = try context.fetch(FetchDescriptor<PadLayoutModel>())
        XCTAssertTrue(layouts.isEmpty)
    }

    // MARK: - PadCellModel.customIconImageName (additive optional column at V2)

    // The pad image-icon filename was added as an additive optional column on the shared
    // `PadCellModel` at V2 (no new versioned schema — see `RegistrySchema.swift`). The
    // in-place column-add cannot be isolated in a single binary (the mutated class is the
    // only definition that exists), so this verifies the column round-trips through a
    // store opened with the real migration plan, as `RegistryStoreFactory` does.
    /// Inserts one pad cell into a fresh V2 store, then releases the container (it goes
    /// out of scope here) so the reopen sees a closed file — mirroring `seedV1Store`.
    private func seedV2Cell(imageName: String?) throws {
        let context = ModelContext(try openV2Store())
        context.insert(PadCellModel(
            id: UUID(), layoutID: UUID(), column: 0, row: 0, columnSpan: 1, rowSpan: 1,
            entryID: nil, backgroundColor: nil,
            customIconName: nil, customIconImageName: imageName, customLabel: nil
        ))
        try context.save()
    }

    func test_customIconImageName_roundTripsThroughStore() throws {
        try seedV2Cell(imageName: "icon.png")
        let cells = try ModelContext(try openV2Store()).fetch(FetchDescriptor<PadCellModel>())
        XCTAssertEqual(cells.first?.customIconImageName, "icon.png")
    }

    func test_customIconImageName_defaultsToNilWhenUnset() throws {
        try seedV2Cell(imageName: nil)
        let cells = try ModelContext(try openV2Store()).fetch(FetchDescriptor<PadCellModel>())
        XCTAssertNil(cells.first?.customIconImageName)
    }

    // MARK: - CategoryModel/EntryModel.isHiddenFromMenuBar (additive Bool column at V2)

    // The menu-bar-visibility flag was added as an additive **non-optional `Bool` with a
    // default** on the shared `CategoryModel`/`EntryModel` (no new versioned schema — see
    // `RegistrySchema.swift`). The precedent (`customIconImageName`) is an *optional* column,
    // so these verify the non-optional-with-default variant also lightweight-migrates: the
    // column round-trips through a store opened with the real migration plan, and a row left
    // unset reads back `false`. As with the icon test, the in-place column-add cannot be
    // isolated in one binary (the mutated class is the only definition that exists).
    private func seedV2Category(hidden: Bool) throws {
        let context = ModelContext(try openV2Store())
        context.insert(CategoryModel(id: UUID(), name: "Cat", sortIndex: 0, isHiddenFromMenuBar: hidden))
        try context.save()
    }

    private func seedV2Entry(hidden: Bool) throws {
        let context = ModelContext(try openV2Store())
        context.insert(EntryModel(
            id: UUID(), name: "Entry", sortIndex: 0, entryType: "command", isHiddenFromMenuBar: hidden
        ))
        try context.save()
    }

    func test_categoryIsHiddenFromMenuBar_roundTripsThroughStore() throws {
        try seedV2Category(hidden: true)
        let categories = try ModelContext(try openV2Store()).fetch(FetchDescriptor<CategoryModel>())
        XCTAssertEqual(categories.first?.isHiddenFromMenuBar, true)
    }

    func test_categoryIsHiddenFromMenuBar_defaultsToFalseWhenUnset() throws {
        try seedV2Category(hidden: false)
        let categories = try ModelContext(try openV2Store()).fetch(FetchDescriptor<CategoryModel>())
        XCTAssertEqual(categories.first?.isHiddenFromMenuBar, false)
    }

    func test_entryIsHiddenFromMenuBar_roundTripsThroughStore() throws {
        try seedV2Entry(hidden: true)
        let entries = try ModelContext(try openV2Store()).fetch(FetchDescriptor<EntryModel>())
        XCTAssertEqual(entries.first?.isHiddenFromMenuBar, true)
    }

    func test_entryIsHiddenFromMenuBar_defaultsToFalseWhenUnset() throws {
        try seedV2Entry(hidden: false)
        let entries = try ModelContext(try openV2Store()).fetch(FetchDescriptor<EntryModel>())
        XCTAssertEqual(entries.first?.isHiddenFromMenuBar, false)
    }
}
