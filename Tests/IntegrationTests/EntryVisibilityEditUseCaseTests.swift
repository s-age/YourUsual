import XCTest
import SwiftData
@testable import YourUsual

/// End-to-end check of the menu-bar-visibility edit path through the REAL composition:
/// `EditEntryUseCase` → `SavedEntryService.editing` → `RegistryDatabaseGateway`
/// (`tx.replaceAllEntries`) → `RegistryDatabase` (`apply`) → `SavedEntryRepository`
/// (`RegisteredItemMapper`). The unit tests cover each link in isolation; this proves the
/// flag survives the full use-case composition a Settings edit actually drives.
final class EntryVisibilityEditUseCaseTests: XCTestCase {
    private var db: RegistryDatabase!
    private var gateway: RegistryDatabaseGateway!
    private var entryService: SavedEntryService!
    private var editEntry: EditEntryUseCase!
    private var readEntries: ReadEntriesUseCase!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: EntryModel.self, CommandRunModel.self, CategoryModel.self,
            BrowseEntryModel.self, CommandEntryModel.self, AppleScriptEntryModel.self,
            configurations: config
        )
        db = RegistryDatabase(modelContainer: container)
        gateway = RegistryDatabaseGateway(runner: db)
        entryService = SavedEntryService(
            repository: SavedEntryRepository(store: db, logger: MockDiagnosticsLogger())
        )
        editEntry = EditEntryUseCase(entries: entryService, db: gateway)
        readEntries = ReadEntriesUseCase(entries: entryService)
    }

    override func tearDown() {
        db = nil
        gateway = nil
        entryService = nil
        editEntry = nil
        readEntries = nil
        super.tearDown()
    }

    private func commandEntry(id: UUID) -> SavedEntry {
        SavedEntry(
            id: id,
            name: "say",
            kind: .command(CommandEntry(line: "say found hi", workingDirectory: nil, sink: .terminal)),
            sortIndex: 0
        )
    }

    func test_editEntry_hidingFromMenuBar_persistsThroughRead() async throws {
        let id = UUID()
        let seed = commandEntry(id: id)
        try await gateway.transaction { tx in try tx.replaceAllEntries([seed]) }

        _ = try await editEntry.execute(
            EditEntryRequest(
                id: id, name: "say",
                kind: .command(CommandPayload(commandLine: "say found hi", workingDirectory: nil, sink: .terminal)),
                isHiddenFromMenuBar: true
            )
        )

        let read = try await readEntries.execute(ReadEntriesRequest())
        XCTAssertEqual(read.first { $0.id == id }?.isHiddenFromMenuBar, true)
    }

    func test_editEntry_keepingVisible_readsAsVisible() async throws {
        let id = UUID()
        let seed = commandEntry(id: id)
        try await gateway.transaction { tx in try tx.replaceAllEntries([seed]) }

        _ = try await editEntry.execute(
            EditEntryRequest(
                id: id, name: "say",
                kind: .command(CommandPayload(commandLine: "say found hi", workingDirectory: nil, sink: .terminal)),
                isHiddenFromMenuBar: false
            )
        )

        let read = try await readEntries.execute(ReadEntriesRequest())
        XCTAssertEqual(read.first { $0.id == id }?.isHiddenFromMenuBar, false)
    }
}
