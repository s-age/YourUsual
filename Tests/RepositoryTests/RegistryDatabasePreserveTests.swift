import XCTest
import SwiftData
@testable import YourUsual

/// Verifies the round-trip preserve rule in `stageReplaceAllEntries`: a `preservingIDs`
/// entry whose row already exists is left untouched (so a decode-recovery placeholder
/// never overwrites the still-intact original), while a normal whole-blob replace still
/// overwrites and deletes as before.
final class RegistryDatabasePreserveTests: XCTestCase {
    private var db: RegistryDatabase!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: EntryModel.self, CommandRunModel.self, CategoryModel.self,
            BrowseEntryModel.self, CommandEntryModel.self, AppleScriptEntryModel.self,
            configurations: config
        )
        db = RegistryDatabase(modelContainer: container)
    }

    override func tearDown() {
        db = nil
        super.tearDown()
    }

    private func commandDTO(id: UUID, name: String) -> RegisteredItemDTO {
        RegisteredItemDTO(
            id: id, name: name, sortIndex: 0,
            targetKind: "command", path: nil, commandLine: "echo \(name)",
            workingDirectory: nil, executable: nil, arguments: nil,
            handlerKind: "background", appBundleIdentifier: nil, terminal: nil
        )
    }

    /// Stages a replace outside the `@Sendable` closure's capture of `self` by building
    /// the DTO first and passing only `Sendable` values in.
    private func stage(_ dto: RegistryDTO, preservingIDs: Set<UUID>) async throws {
        try await db.transaction { tx in try tx.stageReplaceAllEntries(dto, preservingIDs: preservingIDs) }
    }

    func testPreservingID_existingRow_isNotOverwritten() async throws {
        let id = UUID()
        try await stage(RegistryDTO(items: [commandDTO(id: id, name: "Original")]), preservingIDs: [])
        // Re-stage a *different* shape for the same id, but mark it preserved.
        try await stage(RegistryDTO(items: [commandDTO(id: id, name: "Placeholder")]), preservingIDs: [id])
        let stored = try await db.fetchAllEntries()
        XCTAssertEqual(stored.items.first?.name, "Original")
    }

    func testWithoutPreserving_existingRow_isOverwritten() async throws {
        let id = UUID()
        try await stage(RegistryDTO(items: [commandDTO(id: id, name: "Original")]), preservingIDs: [])
        try await stage(RegistryDTO(items: [commandDTO(id: id, name: "Replaced")]), preservingIDs: [])
        let stored = try await db.fetchAllEntries()
        XCTAssertEqual(stored.items.first?.name, "Replaced")
    }

    func testPreservingID_noExistingRow_isInserted() async throws {
        // A preserved id with nothing to preserve (e.g. a fresh import) is inserted.
        let id = UUID()
        try await stage(RegistryDTO(items: [commandDTO(id: id, name: "Imported")]), preservingIDs: [id])
        let stored = try await db.fetchAllEntries()
        XCTAssertEqual(stored.items.first?.name, "Imported")
    }

    func testPreservedSibling_survivesAnotherEntryMutation() async throws {
        // The core data-loss guard: mutating a *sibling* entry must not drop the preserved row.
        let broken = UUID()
        let sibling = UUID()
        try await stage(RegistryDTO(items: [commandDTO(id: broken, name: "Original")]), preservingIDs: [])
        // Add a sibling while the broken entry rides along as a preserved placeholder.
        try await stage(
            RegistryDTO(items: [
                commandDTO(id: broken, name: "Placeholder"),
                commandDTO(id: sibling, name: "Sibling")
            ]),
            preservingIDs: [broken]
        )
        let stored = try await db.fetchAllEntries()
        XCTAssertEqual(stored.items.first { $0.id == broken }?.name, "Original")
    }
}
