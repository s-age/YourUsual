import XCTest
import SwiftData
@testable import YourUsual

/// Exercises the REAL `RegistryDatabase` (SwiftData) through `RegistryDatabaseGateway`
/// + `SavedEntryRepository`, covering upsert-by-id, delete-missing, the per-type
/// payload tables and the edit path — behaviors the `MockEntryStore`-backed
/// `SavedEntryRepositoryTests` cannot reach. Mutations drive `tx.replaceAllEntries`
/// through the UseCase-owned transaction boundary; reads use `SavedEntryRepository`.
final class RegistryDatabaseEntryRoundTripTests: XCTestCase {
    private var db: RegistryDatabase!
    private var sut: RegistryDatabaseGateway!
    private var repo: SavedEntryRepository!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: EntryModel.self, CommandRunModel.self, CategoryModel.self,
            BrowseEntryModel.self, CommandEntryModel.self, AppleScriptEntryModel.self,
            configurations: config
        )
        db = RegistryDatabase(modelContainer: container)
        sut = RegistryDatabaseGateway(runner: db)
        repo = SavedEntryRepository(store: db, logger: MockDiagnosticsLogger())
    }

    override func tearDown() {
        sut = nil
        db = nil
        repo = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func browseEntry(id: UUID = UUID(), app: AppChoice = .default) -> SavedEntry {
        SavedEntry(
            id: id,
            name: "Browse",
            kind: .browse(BrowseEntry(url: URL(fileURLWithPath: "/tmp/test"), app: app)),
            sortIndex: 0
        )
    }

    private func commandEntry(id: UUID = UUID(), sink: CommandSink) -> SavedEntry {
        SavedEntry(
            id: id,
            name: "Cmd",
            kind: .command(CommandEntry(line: "echo hi", workingDirectory: nil, sink: sink)),
            sortIndex: 0
        )
    }

    private func applescriptEntry(id: UUID = UUID()) -> SavedEntry {
        SavedEntry(
            id: id,
            name: "Script",
            kind: .appleScript(AppleScriptEntry(source: "return 42")),
            sortIndex: 0
        )
    }

    private func replace(_ items: [SavedEntry]) async throws {
        try await sut.transaction { tx in try tx.replaceAllEntries(items) }
    }

    private func loaded() async throws -> [SavedEntry] {
        try await repo.listAll()
    }

    private func browseEntry(name: String, sortIndex: Int) -> SavedEntry {
        SavedEntry(
            id: UUID(),
            name: name,
            kind: .browse(BrowseEntry(url: URL(fileURLWithPath: "/\(name)"), app: .default)),
            sortIndex: sortIndex
        )
    }

    // MARK: - Ordering (the store sorts by sortIndex; the repository trusts that order)

    func testListAll_returnsEntriesSortedBySortIndex() async throws {
        try await replace([
            browseEntry(name: "two", sortIndex: 2),
            browseEntry(name: "zero", sortIndex: 0),
            browseEntry(name: "one", sortIndex: 1),
        ])
        let loaded = try await loaded()
        XCTAssertEqual(loaded.map(\.sortIndex), [0, 1, 2])
    }

    // MARK: - Upsert by id

    func testReplaceAll_sameID_doesNotDuplicateRow() async throws {
        let id = UUID()
        try await replace([browseEntry(id: id)])
        try await replace([browseEntry(id: id)])
        let items = try await loaded()
        XCTAssertEqual(items.count, 1)
    }

    // MARK: - Delete-missing

    func testReplaceAll_absentEntry_isRemoved() async throws {
        let kept = browseEntry(id: UUID())
        let dropped = browseEntry(id: UUID())
        try await replace([kept, dropped])
        try await replace([kept])
        let ids = try await loaded().map(\.id)
        XCTAssertFalse(ids.contains(dropped.id))
    }

    func testReplaceAll_absentEntry_doesNotRemoveKeptEntry() async throws {
        let kept = browseEntry(id: UUID())
        let dropped = browseEntry(id: UUID())
        try await replace([kept, dropped])
        try await replace([kept])
        let ids = try await loaded().map(\.id)
        XCTAssertTrue(ids.contains(kept.id))
    }

    func testReplaceAll_emptySet_removesAllEntries() async throws {
        try await replace([browseEntry(), browseEntry()])
        try await replace([])
        let items = try await loaded()
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Browse payload round-trip

    func testRoundTrip_browseEntry_defaultApp_targetKind() async throws {
        try await replace([browseEntry(app: .default)])
        let item = try await loaded().first
        guard case .browse(let b) = item?.kind else { return XCTFail("expected browse") }
        XCTAssertEqual(b.url, URL(fileURLWithPath: "/tmp/test"))
    }

    func testRoundTrip_browseEntry_defaultApp_appChoice() async throws {
        try await replace([browseEntry(app: .default)])
        let item = try await loaded().first
        guard case .browse(let b) = item?.kind else { return XCTFail("expected browse") }
        XCTAssertEqual(b.app, .default)
    }

    func testRoundTrip_browseEntry_specificApp_bundleIdentifier() async throws {
        try await replace([browseEntry(app: .app(bundleIdentifier: "com.apple.finder"))])
        let item = try await loaded().first
        guard case .browse(let b) = item?.kind else { return XCTFail("expected browse") }
        XCTAssertEqual(b.app, .app(bundleIdentifier: "com.apple.finder"))
    }

    // MARK: - Command payload round-trip

    func testRoundTrip_commandEntry_background_handlerKind() async throws {
        try await replace([commandEntry(sink: .background)])
        let item = try await loaded().first
        guard case .command(let c) = item?.kind else { return XCTFail("expected command") }
        XCTAssertEqual(c.sink, .background)
    }

    func testRoundTrip_commandEntry_terminal_handlerKind() async throws {
        try await replace([commandEntry(sink: .terminal)])
        let item = try await loaded().first
        guard case .command(let c) = item?.kind else { return XCTFail("expected command") }
        XCTAssertEqual(c.sink, .terminal)
    }

    func testRoundTrip_commandEntry_commandLine() async throws {
        try await replace([commandEntry(sink: .background)])
        let item = try await loaded().first
        guard case .command(let c) = item?.kind else { return XCTFail("expected command") }
        XCTAssertEqual(c.line, "echo hi")
    }

    // MARK: - AppleScript payload round-trip

    func testRoundTrip_applescriptEntry_source() async throws {
        try await replace([applescriptEntry()])
        let item = try await loaded().first
        guard case .appleScript(let s) = item?.kind else { return XCTFail("expected applescript") }
        XCTAssertEqual(s.source, "return 42")
    }

    // MARK: - Menu-bar visibility round-trip (full store path: mapper + Model↔DTO)

    func testRoundTrip_entry_isHiddenFromMenuBar_true_persists() async throws {
        var entry = browseEntry(id: UUID())
        entry.isHiddenFromMenuBar = true
        try await replace([entry])
        let item = try await loaded().first
        XCTAssertEqual(item?.isHiddenFromMenuBar, true)
    }

    func testRoundTrip_entry_isHiddenFromMenuBar_false_persists() async throws {
        var entry = browseEntry(id: UUID())
        entry.isHiddenFromMenuBar = false
        try await replace([entry])
        let item = try await loaded().first
        XCTAssertEqual(item?.isHiddenFromMenuBar, false)
    }

    // The edit path (`apply` to an existing model) must update the flag, not just creation.
    func testEdit_entry_isHiddenFromMenuBar_visibleToHidden_persists() async throws {
        let id = UUID()
        var visible = browseEntry(id: id)
        visible.isHiddenFromMenuBar = false
        try await replace([visible])
        var hidden = browseEntry(id: id)
        hidden.isHiddenFromMenuBar = true
        try await replace([hidden])
        let item = try await loaded().first
        XCTAssertEqual(item?.isHiddenFromMenuBar, true)
    }

    // MARK: - Edit path (apply to existing model)

    func testEdit_commandSink_backgroundToTerminal_persists() async throws {
        let id = UUID()
        try await replace([commandEntry(id: id, sink: .background)])
        try await replace([commandEntry(id: id, sink: .terminal)])
        let item = try await loaded().first
        guard case .command(let c) = item?.kind else { return XCTFail("expected command") }
        XCTAssertEqual(c.sink, .terminal)
    }

    func testEdit_commandSink_terminalToBackground_persists() async throws {
        let id = UUID()
        try await replace([commandEntry(id: id, sink: .terminal)])
        try await replace([commandEntry(id: id, sink: .background)])
        let item = try await loaded().first
        guard case .command(let c) = item?.kind else { return XCTFail("expected command") }
        XCTAssertEqual(c.sink, .background)
    }

    // MARK: - Edit path — kind change (clearPayload drops the stale payload)
    //
    // The kind is resolved from which payload is non-nil, scanned browse → command →
    // applescript. So an *old* payload that `clearPayload` failed to delete would
    // shadow the new one whenever it precedes it in that order — making these two
    // round-trip assertions also regression guards for a payload leak.

    func testEdit_commandToApplescript_swapsKind() async throws {
        let id = UUID()
        try await replace([commandEntry(id: id, sink: .background)])
        try await replace([applescriptEntry(id: id)])
        let item = try await loaded().first
        guard case .appleScript = item?.kind else {
            return XCTFail("expected applescript after kind change (stale command payload?)")
        }
    }

    func testEdit_browseToCommand_swapsKind() async throws {
        let id = UUID()
        try await replace([browseEntry(id: id)])
        try await replace([commandEntry(id: id, sink: .terminal)])
        let item = try await loaded().first
        guard case .command = item?.kind else {
            return XCTFail("expected command after kind change (stale browse payload?)")
        }
    }

    func testEdit_applescriptToBrowse_swapsKind() async throws {
        let id = UUID()
        try await replace([applescriptEntry(id: id)])
        try await replace([browseEntry(id: id)])
        let item = try await loaded().first
        guard case .browse = item?.kind else { return XCTFail("expected browse after kind change") }
    }
}
