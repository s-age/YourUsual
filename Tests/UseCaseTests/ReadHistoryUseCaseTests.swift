import XCTest
@testable import YourUsual

final class ReadHistoryUseCaseTests: XCTestCase {
    private var sut: ReadHistoryUseCase!
    private var mockHistory: MockRunHistoryService!

    override func setUp() {
        super.setUp()
        mockHistory = MockRunHistoryService()
        sut = ReadHistoryUseCase(history: mockHistory)
    }

    override func tearDown() {
        sut = nil
        mockHistory = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeRecord(
        id: UUID = UUID(),
        entryID: UUID = UUID(),
        entryName: String = "Test",
        executedAt: Date = Date(timeIntervalSinceReferenceDate: 500_000),
        commandLine: String = "echo",
        exitCode: Int32 = 0,
        stdout: String = "out",
        stderr: String = "err"
    ) -> RunRecord {
        RunRecord(
            id: id,
            entryID: entryID,
            entryName: entryName,
            executedAt: executedAt,
            outcome: .command(CommandRunOutcome(
                commandLine: commandLine,
                result: CommandResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
            ))
        )
    }

    // MARK: - entryID routing

    func testExecute_nilEntryID_callsListAll() async throws {
        _ = try await sut.execute(ReadHistoryRequest(entryID: nil))
        XCTAssertEqual(mockHistory.listAllCallCount, 1)
    }

    func testExecute_nilEntryID_doesNotCallListForEntry() async throws {
        _ = try await sut.execute(ReadHistoryRequest(entryID: nil))
        XCTAssertEqual(mockHistory.listForEntryCallCount, 0)
    }

    func testExecute_nonNilEntryID_callsListForEntry() async throws {
        _ = try await sut.execute(ReadHistoryRequest(entryID: UUID()))
        XCTAssertEqual(mockHistory.listForEntryCallCount, 1)
    }

    func testExecute_nonNilEntryID_doesNotCallListAll() async throws {
        _ = try await sut.execute(ReadHistoryRequest(entryID: UUID()))
        XCTAssertEqual(mockHistory.listAllCallCount, 0)
    }

    func testExecute_nonNilEntryID_passesCorrectID() async throws {
        let entryID = UUID()
        _ = try await sut.execute(ReadHistoryRequest(entryID: entryID))
        XCTAssertEqual(mockHistory.listForEntryID, entryID)
    }

    // MARK: - RunRecord → RunHistoryResponse field mapping

    func testExecute_mapsRunRecordID() async throws {
        let id = UUID()
        mockHistory.listAllResult = [makeRecord(id: id)]
        let responses = try await sut.execute(ReadHistoryRequest(entryID: nil))
        XCTAssertEqual(responses.first?.id, id)
    }

    func testExecute_mapsRunRecordEntryID() async throws {
        let entryID = UUID()
        mockHistory.listAllResult = [makeRecord(entryID: entryID)]
        let responses = try await sut.execute(ReadHistoryRequest(entryID: nil))
        XCTAssertEqual(responses.first?.entryID, entryID)
    }

    func testExecute_mapsRunRecordEntryName() async throws {
        mockHistory.listAllResult = [makeRecord(entryName: "Mapped Name")]
        let responses = try await sut.execute(ReadHistoryRequest(entryID: nil))
        XCTAssertEqual(responses.first?.entryName, "Mapped Name")
    }

    func testExecute_mapsRunRecordExecutedAt() async throws {
        let date = Date(timeIntervalSinceReferenceDate: 12_345_678)
        mockHistory.listAllResult = [makeRecord(executedAt: date)]
        let responses = try await sut.execute(ReadHistoryRequest(entryID: nil))
        XCTAssertEqual(responses.first?.executedAt, date)
    }

    func testExecute_mapsRunRecordSucceeded_whenExitCodeZero() async throws {
        mockHistory.listAllResult = [makeRecord(exitCode: 0)]
        let responses = try await sut.execute(ReadHistoryRequest(entryID: nil))
        XCTAssertTrue(responses.first?.succeeded ?? false)
    }

    func testExecute_mapsRunRecordSucceeded_whenExitCodeNonZero() async throws {
        mockHistory.listAllResult = [makeRecord(exitCode: 1)]
        let responses = try await sut.execute(ReadHistoryRequest(entryID: nil))
        XCTAssertFalse(responses.first?.succeeded ?? true)
    }

    func testExecute_mapsRunRecordExitCode() async throws {
        mockHistory.listAllResult = [makeRecord(exitCode: 42)]
        let responses = try await sut.execute(ReadHistoryRequest(entryID: nil))
        XCTAssertEqual(responses.first?.exitCode, 42)
    }

    func testExecute_mapsRunRecordCommandLine() async throws {
        mockHistory.listAllResult = [makeRecord(commandLine: "ls -la /tmp")]
        let responses = try await sut.execute(ReadHistoryRequest(entryID: nil))
        XCTAssertEqual(responses.first?.commandLine, "ls -la /tmp")
    }

    func testExecute_mapsRunRecordStdout() async throws {
        mockHistory.listAllResult = [makeRecord(stdout: "mapped stdout")]
        let responses = try await sut.execute(ReadHistoryRequest(entryID: nil))
        XCTAssertEqual(responses.first?.stdout, "mapped stdout")
    }

    func testExecute_mapsRunRecordStderr() async throws {
        mockHistory.listAllResult = [makeRecord(stderr: "mapped stderr")]
        let responses = try await sut.execute(ReadHistoryRequest(entryID: nil))
        XCTAssertEqual(responses.first?.stderr, "mapped stderr")
    }
}
