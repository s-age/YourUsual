import XCTest
@testable import YourUsual

// MARK: - Mock

final class MockRunHistoryStore: RunHistoryStoreProtocol, @unchecked Sendable {
    var fetchForEntryCallCount = 0
    var fetchForEntryID: UUID?
    var fetchForEntryResult: [RunRecordDTO] = []

    var fetchAllCallCount = 0
    var fetchAllResult: [RunRecordDTO] = []

    func fetch(forEntry id: UUID) async throws -> [RunRecordDTO] {
        fetchForEntryCallCount += 1
        fetchForEntryID = id
        return fetchForEntryResult
    }

    func fetchAllRuns() async throws -> [RunRecordDTO] {
        fetchAllCallCount += 1
        return fetchAllResult
    }
}

// MARK: - Tests

final class RunHistoryRepositoryTests: XCTestCase {
    private var sut: RunHistoryRepository!
    private var mockStore: MockRunHistoryStore!
    private var logger: MockDiagnosticsLogger!

    override func setUp() {
        super.setUp()
        mockStore = MockRunHistoryStore()
        logger = MockDiagnosticsLogger()
        sut = RunHistoryRepository(store: mockStore, logger: logger)
    }

    override func tearDown() {
        sut = nil
        mockStore = nil
        logger = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeDTO(
        id: UUID = UUID(),
        entryID: UUID = UUID(),
        entryName: String = "Test Entry",
        executedAt: Date = Date(timeIntervalSinceReferenceDate: 1_000_000),
        outcomeKind: String = "command",
        commandLine: String? = "echo hello",
        exitCode: Int32? = 0,
        stdout: String? = "hello",
        stderr: String? = ""
    ) -> RunRecordDTO {
        RunRecordDTO(
            id: id,
            entryID: entryID,
            entryName: entryName,
            executedAt: executedAt,
            outcomeKind: outcomeKind,
            commandLine: commandLine,
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr
        )
    }

    // MARK: - list(forEntry:) — DTO → entity conversion

    func testList_commandOutcomeKind_mapsToCommandCase() async throws {
        mockStore.fetchForEntryResult = [makeDTO(outcomeKind: "command")]
        let result = try await sut.list(forEntry: UUID())
        guard case .command = result.first?.outcome else {
            return XCTFail("Expected .command outcome for outcomeKind 'command'")
        }
    }

    func testList_preservesID() async throws {
        let id = UUID()
        mockStore.fetchForEntryResult = [makeDTO(id: id)]
        let result = try await sut.list(forEntry: UUID())
        XCTAssertEqual(result.first?.id, id)
    }

    func testList_preservesEntryName() async throws {
        mockStore.fetchForEntryResult = [makeDTO(entryName: "My Shell Command")]
        let result = try await sut.list(forEntry: UUID())
        XCTAssertEqual(result.first?.entryName, "My Shell Command")
    }

    func testList_preservesCommandLine() async throws {
        mockStore.fetchForEntryResult = [makeDTO(commandLine: "grep -r foo /tmp")]
        let result = try await sut.list(forEntry: UUID())
        guard case .command(let c) = result.first?.outcome else {
            return XCTFail("Expected .command outcome")
        }
        XCTAssertEqual(c.commandLine, "grep -r foo /tmp")
    }

    func testList_preservesExitCode() async throws {
        mockStore.fetchForEntryResult = [makeDTO(exitCode: 1)]
        let result = try await sut.list(forEntry: UUID())
        guard case .command(let c) = result.first?.outcome else {
            return XCTFail("Expected .command outcome")
        }
        XCTAssertEqual(c.exitCode, 1)
    }

    func testList_preservesStdout() async throws {
        mockStore.fetchForEntryResult = [makeDTO(stdout: "round trip stdout")]
        let result = try await sut.list(forEntry: UUID())
        guard case .command(let c) = result.first?.outcome else {
            return XCTFail("Expected .command outcome")
        }
        XCTAssertEqual(c.stdout, "round trip stdout")
    }

    func testList_preservesStderr() async throws {
        mockStore.fetchForEntryResult = [makeDTO(stderr: "round trip stderr")]
        let result = try await sut.list(forEntry: UUID())
        guard case .command(let c) = result.first?.outcome else {
            return XCTFail("Expected .command outcome")
        }
        XCTAssertEqual(c.stderr, "round trip stderr")
    }

    // MARK: - Data-recovery: undecodable record is skipped (treated as absent)

    func testList_unknownOutcomeKind_isSkipped() async throws {
        mockStore.fetchForEntryResult = [makeDTO(outcomeKind: "unknown_future_kind")]
        let result = try await sut.list(forEntry: UUID())
        XCTAssertEqual(result, [])
    }

    func testList_oneMalformedAmongValid_returnsOnlyValidRecords() async throws {
        let valid = makeDTO(id: UUID(), outcomeKind: "command")
        let malformed = makeDTO(id: UUID(), outcomeKind: "unknown_future_kind")
        mockStore.fetchForEntryResult = [valid, malformed]
        let result = try await sut.list(forEntry: UUID())
        XCTAssertEqual(result.map(\.id), [valid.id])
    }

    func testList_malformedRecord_preservesNewestFirstOrderOfValidRecords() async throws {
        let newest = makeDTO(id: UUID(), executedAt: Date(timeIntervalSinceReferenceDate: 3000))
        let malformed = makeDTO(id: UUID(),
                                executedAt: Date(timeIntervalSinceReferenceDate: 2000),
                                outcomeKind: "unknown_future_kind")
        let oldest = makeDTO(id: UUID(), executedAt: Date(timeIntervalSinceReferenceDate: 1000))
        mockStore.fetchForEntryResult = [newest, malformed, oldest]
        let result = try await sut.list(forEntry: UUID())
        XCTAssertEqual(result.map(\.id), [newest.id, oldest.id])
    }

    func testList_unknownOutcomeKind_logsSkipWarning() async throws {
        mockStore.fetchForEntryResult = [makeDTO(outcomeKind: "unknown_future_kind")]
        _ = try await sut.list(forEntry: UUID())
        XCTAssertEqual(logger.warnings.count, 1)
    }

    func testList_validRecord_doesNotLog() async throws {
        mockStore.fetchForEntryResult = [makeDTO(outcomeKind: "command")]
        _ = try await sut.list(forEntry: UUID())
        XCTAssertEqual(logger.warnings.count, 0)
    }

    func testListAll_oneMalformedAmongValid_returnsOnlyValidRecords() async throws {
        let valid = makeDTO(id: UUID(), outcomeKind: "command")
        let malformed = makeDTO(id: UUID(), outcomeKind: "unknown_future_kind")
        mockStore.fetchAllResult = [valid, malformed]
        let result = try await sut.listAll()
        XCTAssertEqual(result.map(\.id), [valid.id])
    }

    // MARK: - listAll()

    func testListAll_callsStoreOnce() async throws {
        _ = try await sut.listAll()
        XCTAssertEqual(mockStore.fetchAllCallCount, 1)
    }

    func testList_passesEntryIDToStore() async throws {
        let id = UUID()
        _ = try await sut.list(forEntry: id)
        XCTAssertEqual(mockStore.fetchForEntryID, id)
    }
}
