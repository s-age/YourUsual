import XCTest
@testable import YourUsual

// MARK: - Mock

final class MockRunHistoryRepository: RunHistoryRepositoryProtocol, @unchecked Sendable {
    var listForEntryCallCount = 0
    var listForEntryID: UUID?
    var listForEntryResult: [RunRecord] = []

    var listAllCallCount = 0
    var listAllResult: [RunRecord] = []

    func list(forEntry id: UUID) async throws -> [RunRecord] {
        listForEntryCallCount += 1
        listForEntryID = id
        return listForEntryResult
    }

    func listAll() async throws -> [RunRecord] {
        listAllCallCount += 1
        return listAllResult
    }
}

// MARK: - Tests

final class RunHistoryServiceTests: XCTestCase {
    private var sut: RunHistoryService!
    private var mockRepository: MockRunHistoryRepository!

    override func setUp() {
        super.setUp()
        mockRepository = MockRunHistoryRepository()
        sut = RunHistoryService(repository: mockRepository)
    }

    override func tearDown() {
        sut = nil
        mockRepository = nil
        super.tearDown()
    }

    private func makeRecord() -> RunRecord {
        RunRecord(
            entryID: UUID(),
            entryName: "X",
            executedAt: Date(),
            outcome: .command(CommandRunOutcome(
                commandLine: "ls",
                result: CommandResult(exitCode: 0, stdout: "", stderr: "")
            ))
        )
    }

    // MARK: - list(forEntry:)

    func testListForEntry_callsRepositoryOnce() async throws {
        _ = try await sut.list(forEntry: UUID())
        XCTAssertEqual(mockRepository.listForEntryCallCount, 1)
    }

    func testListForEntry_passesCorrectID() async throws {
        let id = UUID()
        _ = try await sut.list(forEntry: id)
        XCTAssertEqual(mockRepository.listForEntryID, id)
    }

    func testListForEntry_returnsRepositoryResult() async throws {
        let record = makeRecord()
        mockRepository.listForEntryResult = [record]
        let result = try await sut.list(forEntry: UUID())
        XCTAssertEqual(result, [record])
    }

    // MARK: - listAll()

    func testListAll_callsRepositoryOnce() async throws {
        _ = try await sut.listAll()
        XCTAssertEqual(mockRepository.listAllCallCount, 1)
    }

    func testListAll_returnsRepositoryResult() async throws {
        let record = makeRecord()
        mockRepository.listAllResult = [record]
        let result = try await sut.listAll()
        XCTAssertEqual(result, [record])
    }

    // MARK: - makeRunRecord

    private func makeSUT(now: @escaping @Sendable () -> Date) -> RunHistoryService {
        RunHistoryService(repository: mockRepository, now: now)
    }

    func testRegistering_buildsRecordForGivenEntry() {
        let id = UUID()
        let record = sut.makeRunRecord(
            forEntry: id, named: "Build",
            command: CommandEntry(line: "make", workingDirectory: nil, sink: .background),
            result: CommandResult(exitCode: 0, stdout: "ok", stderr: "")
        )
        XCTAssertEqual(record.entryID, id)
    }

    func testRegistering_snapshotsEntryName() {
        let record = sut.makeRunRecord(
            forEntry: UUID(), named: "Build",
            command: CommandEntry(line: "make", workingDirectory: nil, sink: .background),
            result: CommandResult(exitCode: 0, stdout: "", stderr: "")
        )
        XCTAssertEqual(record.entryName, "Build")
    }

    func testRegistering_wrapsCommandLineAndResultIntoOutcome() {
        let record = sut.makeRunRecord(
            forEntry: UUID(), named: "Build",
            command: CommandEntry(line: "make all", workingDirectory: nil, sink: .background),
            result: CommandResult(exitCode: 2, stdout: "out", stderr: "err")
        )
        guard case .command(let outcome) = record.outcome else {
            return XCTFail("Expected .command outcome")
        }
        XCTAssertEqual(outcome.commandLine, "make all")
        XCTAssertEqual(outcome.exitCode, 2)
    }

    func testRegistering_stampsExecutedAtFromInjectedClock() {
        let fixed = Date(timeIntervalSince1970: 1_000)
        let record = makeSUT(now: { fixed }).makeRunRecord(
            forEntry: UUID(), named: "Build",
            command: CommandEntry(line: "make", workingDirectory: nil, sink: .background),
            result: CommandResult(exitCode: 0, stdout: "", stderr: "")
        )
        XCTAssertEqual(record.executedAt, fixed)
    }
}
