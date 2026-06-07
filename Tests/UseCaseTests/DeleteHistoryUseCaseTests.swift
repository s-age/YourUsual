import Foundation
import XCTest
@testable import YourUsual

// MARK: - Unit-of-Work mocks

/// Records the mutations staged on the transaction token.
final class MockTransaction: Transaction, @unchecked Sendable {
    var registerRunCallCount = 0
    var registeredRun: RunRecord?

    var deleteRunCallCount = 0
    var deletedRunID: UUID?

    var deleteAllRunsForEntryCallCount = 0
    var deleteAllRunsForEntryID: UUID?

    var deleteAllRunsCallCount = 0

    var replaceAllEntriesCallCount = 0
    var replacedEntries: [SavedEntry]?

    var replaceAllCategoriesCallCount = 0
    var replacedCategories: [EntryCategory]?

    var registerPadLayoutCallCount = 0
    var registeredPadLayout: PadLayout?

    var editPadLayoutCallCount = 0
    var editedPadLayout: PadLayout?

    var deletePadLayoutCallCount = 0
    var deletedPadLayoutID: UUID?

    var replacePadCellsCallCount = 0
    var replacedPadCells: [PadCell]?
    var replacedPadCellsLayoutID: UUID?

    func registerRun(_ record: RunRecord) throws {
        registerRunCallCount += 1
        registeredRun = record
    }

    func deleteRun(id: UUID) throws {
        deleteRunCallCount += 1
        deletedRunID = id
    }

    func deleteAllRuns(forEntry id: UUID) throws {
        deleteAllRunsForEntryCallCount += 1
        deleteAllRunsForEntryID = id
    }

    func deleteAllRuns() throws {
        deleteAllRunsCallCount += 1
    }

    func replaceAllEntries(_ items: [SavedEntry]) throws {
        replaceAllEntriesCallCount += 1
        replacedEntries = items
    }

    func replaceAllCategories(_ categories: [EntryCategory]) throws {
        replaceAllCategoriesCallCount += 1
        replacedCategories = categories
    }

    func registerPadLayout(_ layout: PadLayout) throws {
        registerPadLayoutCallCount += 1
        registeredPadLayout = layout
    }

    func editPadLayout(_ layout: PadLayout) throws {
        editPadLayoutCallCount += 1
        editedPadLayout = layout
    }

    func deletePadLayout(id: UUID) throws {
        deletePadLayoutCallCount += 1
        deletedPadLayoutID = id
    }

    func replacePadCells(layoutID: UUID, cells: [PadCell]) throws {
        replacePadCellsCallCount += 1
        replacedPadCellsLayoutID = layoutID
        replacedPadCells = cells
    }
}

/// Runs `body` against a shared `MockTransaction` so tests can assert which
/// mutation the use case staged inside the transaction boundary.
final class MockDB: DBProtocol, @unchecked Sendable {
    let tx = MockTransaction()
    var transactionCallCount = 0
    /// When true, `transaction` throws before running `body` — simulates a storage failure.
    var shouldThrow = false

    struct MockPerformError: Error {}

    func transaction<T: Sendable>(
        _ body: @Sendable (any Transaction) throws -> T
    ) async throws -> T {
        transactionCallCount += 1
        if shouldThrow { throw MockPerformError() }
        return try body(tx)
    }
}

// MARK: - Tests

final class DeleteHistoryUseCaseTests: XCTestCase {
    private var sut: DeleteHistoryUseCase!
    private var mockDB: MockDB!

    override func setUp() {
        super.setUp()
        mockDB = MockDB()
        sut = DeleteHistoryUseCase(db: mockDB)
    }

    override func tearDown() {
        sut = nil
        mockDB = nil
        super.tearDown()
    }

    // MARK: - Transaction boundary

    func testExecute_runsInsideOneTransaction() async throws {
        try await sut.execute(DeleteHistoryRequest(scope: .all))
        XCTAssertEqual(mockDB.transactionCallCount, 1)
    }

    // MARK: - Scope.run

    func testExecute_scopeRun_callsDeleteRunOnce() async throws {
        try await sut.execute(DeleteHistoryRequest(scope: .run(UUID())))
        XCTAssertEqual(mockDB.tx.deleteRunCallCount, 1)
    }

    func testExecute_scopeRun_passesCorrectID() async throws {
        let id = UUID()
        try await sut.execute(DeleteHistoryRequest(scope: .run(id)))
        XCTAssertEqual(mockDB.tx.deletedRunID, id)
    }

    func testExecute_scopeRun_doesNotCallDeleteAllForEntry() async throws {
        try await sut.execute(DeleteHistoryRequest(scope: .run(UUID())))
        XCTAssertEqual(mockDB.tx.deleteAllRunsForEntryCallCount, 0)
    }

    func testExecute_scopeRun_doesNotCallDeleteAll() async throws {
        try await sut.execute(DeleteHistoryRequest(scope: .run(UUID())))
        XCTAssertEqual(mockDB.tx.deleteAllRunsCallCount, 0)
    }

    // MARK: - Scope.entry

    func testExecute_scopeEntry_callsDeleteAllForEntryOnce() async throws {
        try await sut.execute(DeleteHistoryRequest(scope: .entry(UUID())))
        XCTAssertEqual(mockDB.tx.deleteAllRunsForEntryCallCount, 1)
    }

    func testExecute_scopeEntry_passesCorrectID() async throws {
        let id = UUID()
        try await sut.execute(DeleteHistoryRequest(scope: .entry(id)))
        XCTAssertEqual(mockDB.tx.deleteAllRunsForEntryID, id)
    }

    func testExecute_scopeEntry_doesNotCallDelete() async throws {
        try await sut.execute(DeleteHistoryRequest(scope: .entry(UUID())))
        XCTAssertEqual(mockDB.tx.deleteRunCallCount, 0)
    }

    func testExecute_scopeEntry_doesNotCallDeleteAll() async throws {
        try await sut.execute(DeleteHistoryRequest(scope: .entry(UUID())))
        XCTAssertEqual(mockDB.tx.deleteAllRunsCallCount, 0)
    }

    // MARK: - Scope.all

    func testExecute_scopeAll_callsDeleteAllOnce() async throws {
        try await sut.execute(DeleteHistoryRequest(scope: .all))
        XCTAssertEqual(mockDB.tx.deleteAllRunsCallCount, 1)
    }

    func testExecute_scopeAll_doesNotCallDelete() async throws {
        try await sut.execute(DeleteHistoryRequest(scope: .all))
        XCTAssertEqual(mockDB.tx.deleteRunCallCount, 0)
    }

    func testExecute_scopeAll_doesNotCallDeleteAllForEntry() async throws {
        try await sut.execute(DeleteHistoryRequest(scope: .all))
        XCTAssertEqual(mockDB.tx.deleteAllRunsForEntryCallCount, 0)
    }
}
