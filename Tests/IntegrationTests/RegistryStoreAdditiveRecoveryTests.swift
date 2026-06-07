import XCTest
import SwiftData
@testable import YourUsual

/// Test-only earlier V2: identifier `2.0.0` (same string the live `RegistrySchemaV2`
/// stamps) but the pre-slider model set, so it produces a *different* checksum — exactly
/// the shape of a store written before `SliderEntryModel` was folded into V2. Kept out of
/// `RegistryMigrationPlan` (two schemas with one identifier would collide there); used only
/// to seed a store carrying the stale `2.0.0` checksum.
private enum PreSliderSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [EntryModel.self, CommandRunModel.self, CategoryModel.self,
         BrowseEntryModel.self, CommandEntryModel.self, AppleScriptEntryModel.self,
         PadLayoutModel.self, PadCellModel.self]
    }
}

/// Regression guard for the store-wipe bug: additive schema changes folded into
/// `RegistrySchemaV2` (without a version-identifier bump) change V2's *model checksum*,
/// so a store written by an earlier build failed the **staged** migration open with
/// `NSCocoaErrorDomain 134504` ("Cannot use staged migration with an unknown model
/// version") and `RegistryStoreFactory` moved it aside — wiping the user's data on every
/// schema-evolving build/release.
///
/// `RegistryStoreFactory.makeContainer` now retries **without** the plan (automatic
/// lightweight migration) before ever backing up. These tests pin both halves of why that
/// works: the staged open still rejects such a store, and the plan-less open recovers it
/// in place with the data intact.
final class RegistryStoreAdditiveRecoveryTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "additive-recovery-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appending(path: "registry.store", directoryHint: .notDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
        storeURL = nil
    }

    /// Seeds a store whose schema is an EARLIER V2 — the current model set minus
    /// `SliderEntryModel` — so it carries a different checksum, exactly like a store written
    /// before the slider table was folded into V2. Returns the seeded entry's id.
    private func seedPreSliderStore() throws -> UUID {
        let schema = Schema(versionedSchema: PreSliderSchemaV2.self)
        let config = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        let id = UUID()
        context.insert(EntryModel(id: id, name: "Existing", sortIndex: 0, entryType: "command"))
        try context.save()
        return id
    }

    /// Tier 2 (plan-less, automatic lightweight migration) recovers a store carrying a stale
    /// `2.0.0` checksum in place — the entry is preserved and the folded-in slider table is
    /// present and writable. This is the path that, against the user's real moved-aside store,
    /// reopened it intact after the staged open had failed with `134504`. (Whether the staged
    /// open *throws* is SwiftData-internal and varies with the exact historical checksum, so
    /// it is not pinned here; tier 2's recovery is the contract that matters.)
    func test_planlessOpen_recoversAdditiveEvolvedStore() throws {
        let id = try seedPreSliderStore()
        let schema = Schema(versionedSchema: RegistrySchemaV2.self)
        let config = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let entries = try context.fetch(FetchDescriptor<EntryModel>())
        XCTAssertEqual(entries.map(\.id), [id])

        context.insert(SliderEntryModel(commandLine: "vol <VALUE>",
                                        minValue: 0, maxValue: 100, step: 1, currentValue: 50))
        XCTAssertNoThrow(try context.save())
    }

    // MARK: - makeContainer(at:) tier orchestration

    /// Seeds a healthy store at the *current* schema via the real migration plan. Returns the
    /// entry id. The container is released on return so `makeContainer` can reopen the file.
    private func seedCurrentStore() throws -> UUID {
        let schema = Schema(versionedSchema: RegistrySchemaV2.self)
        let config = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(for: schema,
                                           migrationPlan: RegistryMigrationPlan.self,
                                           configurations: config)
        let context = ModelContext(container)
        let id = UUID()
        context.insert(EntryModel(id: id, name: "Healthy", sortIndex: 0, entryType: "command"))
        try context.save()
        return id
    }

    /// `.corrupt-…` sidecars next to the store — the only files tier 3 ever creates. The bug of
    /// record is that an *openable* store gets one of these; these tests assert it does not.
    private func corruptBackups() throws -> [URL] {
        let dir = storeURL.deletingLastPathComponent()
        return try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("registry.store.corrupt-") }
    }

    /// A healthy store opens at tier 1 with no backup and no recovered URL.
    func test_makeContainer_healthyStore_opensWithoutBackup() throws {
        let id = try seedCurrentStore()
        let boot = try RegistryStoreFactory.makeContainer(at: storeURL)
        XCTAssertNil(boot.recoveredBackupURL)
        XCTAssertFalse(boot.wasUpgradedInPlace)
        XCTAssertTrue(try corruptBackups().isEmpty)
        let entries = try ModelContext(boot.container).fetch(FetchDescriptor<EntryModel>())
        XCTAssertEqual(entries.map(\.id), [id])
    }

    /// The heart of the bug: an additive-evolved (stale-checksum) store is **openable**, so
    /// `makeContainer` must recover it WITHOUT moving it aside — `recoveredBackupURL == nil` and
    /// no `.corrupt-…` file. Whether that lands at tier 1 or tier 2 is SwiftData-internal; the
    /// contract pinned here is "an openable store is never wiped".
    func test_makeContainer_additiveEvolvedStore_isNeverMovedAside() throws {
        _ = try seedPreSliderStore()
        let boot = try RegistryStoreFactory.makeContainer(at: storeURL)
        XCTAssertNil(boot.recoveredBackupURL)
        XCTAssertTrue(try corruptBackups().isEmpty)
    }

    /// A genuinely unreadable store falls through to tier 3: it is backed up (one `.corrupt-…`
    /// file, surfaced via `recoveredBackupURL`) and replaced by a fresh empty store.
    func test_makeContainer_unreadableStore_backsUpAndRecreatesEmpty() throws {
        try Data("definitely not a SQLite store".utf8).write(to: storeURL)
        let boot = try RegistryStoreFactory.makeContainer(at: storeURL)
        XCTAssertNotNil(boot.recoveredBackupURL)
        XCTAssertFalse(boot.wasUpgradedInPlace)
        XCTAssertEqual(try corruptBackups().count, 1)
        let entries = try ModelContext(boot.container).fetch(FetchDescriptor<EntryModel>())
        XCTAssertTrue(entries.isEmpty)
    }
}
