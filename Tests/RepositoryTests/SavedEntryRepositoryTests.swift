import XCTest
@testable import YourUsual

// MARK: - Mock

final class MockEntryStore: EntryStoreProtocol, @unchecked Sendable {
    var stored: RegistryDTO?
    var fetchAllCallCount = 0

    func fetchAllEntries() throws -> RegistryDTO {
        fetchAllCallCount += 1
        // Emulate the real store's contract: entries come out sorted by sortIndex
        // (the repository trusts this order rather than re-sorting).
        let items = (stored ?? RegistryDTO(items: [])).items.sorted { $0.sortIndex < $1.sortIndex }
        return RegistryDTO(items: items)
    }
}

final class SavedEntryRepositoryTests: XCTestCase {
    private var sut: SavedEntryRepository!
    private var store: MockEntryStore!
    private var logger: MockDiagnosticsLogger!

    override func setUp() {
        super.setUp()
        store = MockEntryStore()
        logger = MockDiagnosticsLogger()
        sut = SavedEntryRepository(store: store, logger: logger)
    }

    override func tearDown() {
        sut = nil
        store = nil
        logger = nil
        super.tearDown()
    }

    private func browseDTO(
        id: UUID = UUID(),
        name: String,
        path: String,
        sortIndex: Int,
        handlerKind: String = "defaultApp",
        categoryID: UUID? = nil
    ) -> RegisteredItemDTO {
        RegisteredItemDTO(
            id: id, name: name, sortIndex: sortIndex,
            targetKind: "path", path: path, commandLine: nil,
            workingDirectory: nil, executable: nil, arguments: nil,
            handlerKind: handlerKind, appBundleIdentifier: nil, terminal: nil,
            applescriptSource: nil, categoryID: categoryID
        )
    }

    // MARK: - Round-trip per EntryKind variant

    func test_roundTrip_browse_defaultApp_preservesItem() async throws {
        let id = UUID()
        store.stored = RegistryDTO(items: [browseDTO(id: id, name: "Notes", path: "/tmp/notes.txt", sortIndex: 0)])
        let loaded = try await sut.listAll()
        XCTAssertEqual(loaded.first?.name, "Notes")
        XCTAssertEqual(loaded.first?.id, id)
    }

    func test_roundTrip_browse_app_preservesBundleID() async throws {
        store.stored = RegistryDTO(items: [
            RegisteredItemDTO(
                id: UUID(), name: "Open in TextEdit", sortIndex: 1,
                targetKind: "path", path: "/tmp/notes.txt", commandLine: nil,
                workingDirectory: nil, executable: nil, arguments: nil,
                handlerKind: "app", appBundleIdentifier: "com.apple.TextEdit", terminal: nil
            )
        ])
        let loaded = try await sut.listAll()
        guard case .browse(let browse) = loaded.first?.kind else {
            return XCTFail("Expected browse entry")
        }
        XCTAssertEqual(browse.app, .app(bundleIdentifier: "com.apple.TextEdit"))
    }

    func test_roundTrip_command_background_preservesItem() async throws {
        store.stored = RegistryDTO(items: [
            RegisteredItemDTO(
                id: UUID(), name: "List", sortIndex: 2,
                targetKind: "command", path: nil, commandLine: "/bin/ls -la",
                workingDirectory: "/tmp", executable: nil, arguments: nil,
                handlerKind: "background", appBundleIdentifier: nil, terminal: nil
            )
        ])
        let loaded = try await sut.listAll()
        guard case .command(let command) = loaded.first?.kind else {
            return XCTFail("Expected command entry")
        }
        XCTAssertEqual(command.line, "/bin/ls -la")
        XCTAssertEqual(command.sink, .background)
    }

    func test_roundTrip_command_terminal_preservesSink() async throws {
        store.stored = RegistryDTO(items: [
            RegisteredItemDTO(
                id: UUID(), name: "Top", sortIndex: 3,
                targetKind: "command", path: nil, commandLine: "/usr/bin/top",
                workingDirectory: nil, executable: nil, arguments: nil,
                handlerKind: "terminal", appBundleIdentifier: nil, terminal: nil
            )
        ])
        let loaded = try await sut.listAll()
        guard case .command(let command) = loaded.first?.kind else {
            return XCTFail("Expected command entry")
        }
        XCTAssertEqual(command.sink, .terminal)
    }

    // MARK: - Sorting
    // The sort itself is the store's contract (verified against the real store in
    // RegistryDatabaseEntryRoundTripTests); here we assert the repository *surfaces* that
    // order unchanged — the mock store emulates the sorted contract.

    func test_listAll_surfacesStoreSortOrder() async throws {
        store.stored = RegistryDTO(items: [
            browseDTO(name: "two", path: "/2", sortIndex: 2),
            browseDTO(name: "zero", path: "/0", sortIndex: 0),
            browseDTO(name: "one", path: "/1", sortIndex: 1),
        ])
        let sorted = try await sut.listAll()
        XCTAssertEqual(sorted.map(\.sortIndex), [0, 1, 2])
    }

    // MARK: - Legacy fallback (pre-shell executable + arguments)

    func test_loadItems_legacyExecutableArguments_decodesCommandLine() async throws {
        store.stored = RegistryDTO(items: [
            RegisteredItemDTO(
                id: UUID(), name: "legacy", sortIndex: 0,
                targetKind: "command", path: nil, commandLine: nil,
                workingDirectory: nil, executable: "/bin/ls", arguments: ["-la", "/tmp"],
                handlerKind: "background", appBundleIdentifier: nil, terminal: nil
            ),
        ])
        let loaded = try await sut.listAll()
        guard case .command(let command) = loaded.first?.kind else {
            return XCTFail("Expected a command entry")
        }
        XCTAssertEqual(command.line, "/bin/ls -la /tmp")
    }

    // MARK: - Corrupt kinds → data-recovery to empty File/Directory entry (no throw)

    func test_loadItems_unknownTargetKind_recoversAsBrowseEntry() async throws {
        let id = UUID()
        store.stored = RegistryDTO(items: [
            RegisteredItemDTO(
                id: id, name: "bad", sortIndex: 0,
                targetKind: "bogus", path: "/tmp", commandLine: nil,
                workingDirectory: nil, executable: nil, arguments: nil,
                handlerKind: "defaultApp", appBundleIdentifier: nil, terminal: nil
            ),
        ])
        let loaded = try await sut.listAll()
        guard case .browse(let browse) = loaded.first?.kind else {
            return XCTFail("Expected the corrupt record to recover as a browse entry")
        }
        XCTAssertEqual(browse.app, .default)
    }

    func test_loadItems_unknownTargetKind_preservesPath() async throws {
        store.stored = RegistryDTO(items: [
            RegisteredItemDTO(
                id: UUID(), name: "bad", sortIndex: 0,
                targetKind: "bogus", path: "/tmp/recovered", commandLine: nil,
                workingDirectory: nil, executable: nil, arguments: nil,
                handlerKind: "defaultApp", appBundleIdentifier: nil, terminal: nil
            ),
        ])
        let loaded = try await sut.listAll()
        guard case .browse(let browse) = loaded.first?.kind else {
            return XCTFail("Expected a browse entry")
        }
        XCTAssertEqual(browse.url.path, "/tmp/recovered")
    }

    func test_loadItems_browseWithCommandHandler_recoversAsBrowseEntry() async throws {
        store.stored = RegistryDTO(items: [
            RegisteredItemDTO(
                id: UUID(), name: "bad", sortIndex: 0,
                targetKind: "path", path: "/tmp", commandLine: nil,
                workingDirectory: nil, executable: nil, arguments: nil,
                handlerKind: "background", appBundleIdentifier: nil, terminal: nil
            ),
        ])
        let loaded = try await sut.listAll()
        guard case .browse(let browse) = loaded.first?.kind else {
            return XCTFail("Expected the corrupt record to recover as a browse entry")
        }
        XCTAssertEqual(browse.app, .default)
    }

    func test_loadItems_commandWithBrowseHandler_recoversAsBrowseEntry() async throws {
        store.stored = RegistryDTO(items: [
            RegisteredItemDTO(
                id: UUID(), name: "bad", sortIndex: 0,
                targetKind: "command", path: nil, commandLine: "/bin/ls",
                workingDirectory: nil, executable: nil, arguments: nil,
                handlerKind: "defaultApp", appBundleIdentifier: nil, terminal: nil
            ),
        ])
        let loaded = try await sut.listAll()
        guard case .browse = loaded.first?.kind else {
            return XCTFail("Expected the corrupt record to recover as a browse entry")
        }
    }

    func test_loadItems_commandMissingLine_recoversAsBrowseEntryWithNoPreservedPath() async throws {
        store.stored = RegistryDTO(items: [
            RegisteredItemDTO(
                id: UUID(), name: "bad", sortIndex: 0,
                targetKind: "command", path: nil, commandLine: nil,
                workingDirectory: nil, executable: nil, arguments: nil,
                handlerKind: "background", appBundleIdentifier: nil, terminal: nil
            ),
        ])
        let loaded = try await sut.listAll()
        guard case .browse(let browse) = loaded.first?.kind else {
            return XCTFail("Expected a browse entry")
        }
        XCTAssertEqual(browse.url, URL(fileURLWithPath: ""))
    }

    // MARK: - One malformed record must not fail the whole list

    func test_loadItems_oneMalformedAmongValid_returnsAllRecords() async throws {
        store.stored = RegistryDTO(items: [
            RegisteredItemDTO(
                id: UUID(), name: "good", sortIndex: 0,
                targetKind: "path", path: "/tmp/good", commandLine: nil,
                workingDirectory: nil, executable: nil, arguments: nil,
                handlerKind: "defaultApp", appBundleIdentifier: nil, terminal: nil
            ),
            RegisteredItemDTO(
                id: UUID(), name: "bad", sortIndex: 1,
                targetKind: "bogus", path: nil, commandLine: nil,
                workingDirectory: nil, executable: nil, arguments: nil,
                handlerKind: "whatever", appBundleIdentifier: nil, terminal: nil
            ),
        ])
        let loaded = try await sut.listAll()
        XCTAssertEqual(loaded.count, 2)
    }

    func test_loadItems_malformedRecord_logsRecoveryWarning() async throws {
        store.stored = RegistryDTO(items: [malformedDTO()])
        _ = try await sut.listAll()
        XCTAssertEqual(logger.warnings.count, 1)
    }

    func test_loadItems_validRecord_doesNotLog() async throws {
        store.stored = RegistryDTO(items: [browseDTO(name: "ok", path: "/tmp", sortIndex: 0)])
        _ = try await sut.listAll()
        XCTAssertEqual(logger.warnings.count, 0)
    }

    func test_loadItems_malformedRecord_preservesID() async throws {
        let id = UUID()
        store.stored = RegistryDTO(items: [malformedDTO(id: id)])
        let recovered = try await sut.listAll().first
        XCTAssertEqual(recovered?.id, id)
    }

    func test_loadItems_malformedRecord_preservesName() async throws {
        store.stored = RegistryDTO(items: [malformedDTO(name: "bad")])
        let recovered = try await sut.listAll().first
        XCTAssertEqual(recovered?.name, "bad")
    }

    func test_loadItems_malformedRecord_preservesSortIndex() async throws {
        store.stored = RegistryDTO(items: [malformedDTO(sortIndex: 7)])
        let recovered = try await sut.listAll().first
        XCTAssertEqual(recovered?.sortIndex, 7)
    }

    func test_loadItems_malformedRecord_preservesCategoryID() async throws {
        let categoryID = UUID()
        store.stored = RegistryDTO(items: [malformedDTO(categoryID: categoryID)])
        let recovered = try await sut.listAll().first
        XCTAssertEqual(recovered?.categoryID, categoryID)
    }

    func test_loadItems_malformedRecord_isMarkedRecovered() async throws {
        store.stored = RegistryDTO(items: [malformedDTO()])
        let recovered = try await sut.listAll().first
        XCTAssertEqual(recovered?.isRecovered, true)
    }

    func test_loadItems_validRecord_isNotMarkedRecovered() async throws {
        store.stored = RegistryDTO(items: [browseDTO(name: "Notes", path: "/tmp/n.txt", sortIndex: 0)])
        let loaded = try await sut.listAll().first
        XCTAssertEqual(loaded?.isRecovered, false)
    }

    // MARK: - Empty store

    func test_loadItems_noFile_returnsEmpty() async throws {
        store.stored = nil
        let empty = try await sut.listAll()
        XCTAssertEqual(empty, [])
    }

    // MARK: - Helpers

    private func malformedDTO(
        id: UUID = UUID(),
        name: String = "bad",
        sortIndex: Int = 0,
        categoryID: UUID = UUID()
    ) -> RegisteredItemDTO {
        RegisteredItemDTO(
            id: id, name: name, sortIndex: sortIndex,
            targetKind: "bogus", path: nil, commandLine: nil,
            workingDirectory: nil, executable: nil, arguments: nil,
            handlerKind: "whatever", appBundleIdentifier: nil, terminal: nil,
            applescriptSource: nil, categoryID: categoryID
        )
    }
}
