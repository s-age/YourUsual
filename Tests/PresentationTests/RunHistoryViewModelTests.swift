import XCTest
@testable import YourUsual

// MARK: - Mocks

final class MockReadHistoryUseCase: AsyncUseCase, @unchecked Sendable {
    var callCount = 0
    var result: [RunHistoryResponse] = []
    var error: Error?
    var onExecute: (@MainActor () -> Void)?

    func execute(_ request: ReadHistoryRequest) async throws -> [RunHistoryResponse] {
        callCount += 1
        await onExecute?()
        if let error { throw error }
        return result
    }
}

final class MockDeleteHistoryUseCase: AsyncUseCase, @unchecked Sendable {
    var callCount = 0
    var receivedScope: DeleteHistoryRequest.Scope?
    var error: Error?

    func execute(_ request: DeleteHistoryRequest) async throws {
        callCount += 1
        receivedScope = request.scope
        if let error { throw error }
    }
}

// MARK: - Tests

@MainActor
final class RunHistoryViewModelTests: XCTestCase {
    private var sut: RunHistoryViewModel!
    private var mockRead: MockReadHistoryUseCase!
    private var mockDelete: MockDeleteHistoryUseCase!

    override func setUp() async throws {
        try await super.setUp()
        mockRead = MockReadHistoryUseCase()
        mockDelete = MockDeleteHistoryUseCase()
        sut = RunHistoryViewModel(
            entryID: nil,
            title: "History",
            readHistory: mockRead,
            deleteHistory: mockDelete
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockRead = nil
        mockDelete = nil
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func makeResponse(
        id: UUID = UUID(),
        entryID: UUID = UUID()
    ) -> RunHistoryResponse {
        RunHistoryResponse(
            id: id,
            entryID: entryID,
            entryName: "Test",
            executedAt: Date(),
            succeeded: true,
            exitCode: 0,
            commandLine: "echo",
            stdout: "",
            stderr: ""
        )
    }

    // MARK: - load()

    func testLoad_populatesRuns() async {
        let runs = [makeResponse(), makeResponse()]
        mockRead.result = runs
        await sut.load()
        XCTAssertEqual(sut.runs, runs)
    }

    func testLoad_setsEmptyRunsOnError() async {
        mockRead.error = OperationError.persistenceFailed(reason: "boom")
        await sut.load()
        XCTAssertEqual(sut.runs, [])
    }

    // MARK: - delete(_:)

    func testDelete_callsDeleteHistoryWithRunScope() async {
        let run = makeResponse()
        await sut.delete(run)
        if case .run(let id) = mockDelete.receivedScope {
            XCTAssertEqual(id, run.id)
        } else {
            XCTFail("Expected .run(run.id) scope, got \(String(describing: mockDelete.receivedScope))")
        }
    }

    func testDelete_reloadsAfterDelete() async {
        let before = mockRead.callCount
        await sut.delete(makeResponse())
        XCTAssertEqual(mockRead.callCount, before + 1)
    }

    // MARK: - clearAll()

    func testClearAll_withEntryID_usesEntryScope() async {
        let entryID = UUID()
        sut = RunHistoryViewModel(
            entryID: entryID,
            title: "Entry History",
            readHistory: mockRead,
            deleteHistory: mockDelete
        )
        await sut.clearAll()
        if case .entry(let id) = mockDelete.receivedScope {
            XCTAssertEqual(id, entryID)
        } else {
            XCTFail("Expected .entry(entryID) scope, got \(String(describing: mockDelete.receivedScope))")
        }
    }

    func testClearAll_withoutEntryID_usesAllScope() async {
        // sut is configured with entryID: nil in setUp
        await sut.clearAll()
        if case .all = mockDelete.receivedScope {
            // correct
        } else {
            XCTFail("Expected .all scope, got \(String(describing: mockDelete.receivedScope))")
        }
    }

    func testClearAll_reloadsAfterClear() async {
        let before = mockRead.callCount
        await sut.clearAll()
        XCTAssertEqual(mockRead.callCount, before + 1)
    }
}
