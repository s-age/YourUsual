import XCTest
import SwiftData
@testable import YourUsual

/// Exercises the one-shot legacy import end-to-end across the layers it now spans:
/// `LegacyRegistryReader` (Infra transport read) → `LegacyRegistryRepository`
/// (DTO→entity) → `LegacyMigrationService.importingLegacy` (the empty-store decision) →
/// `MigrateLegacyRegistryUseCase` (the transaction boundary, via the real gateway)
/// against an in-memory `RegistryDatabase`.
///
/// Focus (unchanged from the former migrator test): a present-but-corrupt legacy
/// file must surface as a thrown error rather than being swallowed; absent/valid/
/// already-populated stay quiet no-ops or import cleanly.
final class MigrateLegacyRegistryTests: XCTestCase {
    private var db: RegistryDatabase!
    private var legacyURL: URL!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: EntryModel.self, CommandRunModel.self, CategoryModel.self,
            BrowseEntryModel.self, CommandEntryModel.self, AppleScriptEntryModel.self,
            configurations: config
        )
        db = RegistryDatabase(modelContainer: container)
        legacyURL = FileManager.default.temporaryDirectory
            .appending(path: "legacy-\(UUID().uuidString).json", directoryHint: .notDirectory)
    }

    override func tearDown() {
        if let legacyURL { try? FileManager.default.removeItem(at: legacyURL) }
        db = nil
        legacyURL = nil
        super.tearDown()
    }

    /// Wires the real stack the boot path uses, with the in-memory `db` as both store
    /// and transaction runner and a `legacyURL` pointing at this test's temp file.
    private func makeUseCase() -> MigrateLegacyRegistryUseCaseProtocol {
        let logger = OSDiagnosticsLogger(category: "MigrateLegacyRegistryTests")
        let reader = LegacyRegistryReader(legacyURL: legacyURL)
        let legacyRepository = LegacyRegistryRepository(reader: reader, logger: logger)
        let entryRepository = SavedEntryRepository(store: db, logger: logger)
        let migration = LegacyMigrationService(
            repository: entryRepository,
            legacyRepository: legacyRepository
        )
        return MigrateLegacyRegistryUseCase(
            migration: migration,
            db: RegistryDatabaseGateway(runner: db)
        )
    }

    private func makeEntryDTO() -> RegisteredItemDTO {
        RegisteredItemDTO(
            id: UUID(), name: "Entry", sortIndex: 0,
            targetKind: "command", path: nil, commandLine: "echo hi",
            workingDirectory: nil, executable: nil, arguments: nil,
            handlerKind: "background", appBundleIdentifier: nil, terminal: nil
        )
    }

    // MARK: - Absent legacy file (fresh install — normal path)

    func testMigrate_whenLegacyFileAbsent_doesNotThrow() async throws {
        try await makeUseCase().execute(MigrateLegacyRegistryRequest())
    }

    func testMigrate_whenLegacyFileAbsent_leavesStoreEmpty() async throws {
        try await makeUseCase().execute(MigrateLegacyRegistryRequest())
        let stored = try await db.fetchAllEntries()
        XCTAssertTrue(stored.items.isEmpty)
    }

    // MARK: - Present but corrupt (the no-longer-silent failure)

    func testMigrate_whenLegacyFileCorrupt_throwsPersistenceFailed() async throws {
        try Data("{ not valid json".utf8).write(to: legacyURL)
        do {
            try await makeUseCase().execute(MigrateLegacyRegistryRequest())
            XCTFail("Expected a persistenceFailed error for a corrupt legacy file")
        } catch let error as OperationError {
            guard case .persistenceFailed = error else {
                return XCTFail("Expected .persistenceFailed, got \(error)")
            }
        }
    }

    func testMigrate_whenLegacyFileCorrupt_leavesStoreEmpty() async throws {
        try Data("{ not valid json".utf8).write(to: legacyURL)
        try? await makeUseCase().execute(MigrateLegacyRegistryRequest())
        let stored = try await db.fetchAllEntries()
        XCTAssertTrue(stored.items.isEmpty)
    }

    // MARK: - Present and valid (successful import)

    func testMigrate_whenLegacyFileValid_importsEntries() async throws {
        let dto = RegistryDTO(items: [makeEntryDTO()])
        try JSONEncoder().encode(dto).write(to: legacyURL)
        try await makeUseCase().execute(MigrateLegacyRegistryRequest())
        let stored = try await db.fetchAllEntries()
        XCTAssertEqual(stored.items.count, 1)
    }

    // MARK: - Already populated (idempotent — even with a corrupt file present)

    func testMigrate_whenStoreAlreadyPopulated_isNoOpDespiteCorruptFile() async throws {
        // Seed the store so the registry is non-empty, then point at a corrupt file.
        // The empty-store decision returns nil before the file is ever read.
        let seed = RegistryDTO(items: [makeEntryDTO()])
        try await db.transaction { tx in
            try tx.stageReplaceAllEntries(seed, preservingIDs: [])
        }
        try Data("{ not valid json".utf8).write(to: legacyURL)
        try await makeUseCase().execute(MigrateLegacyRegistryRequest())   // must not throw
    }
}
