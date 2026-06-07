import XCTest
@testable import YourUsual

final class DeleteEntryUseCaseTests: XCTestCase {
    private var sut: DeleteEntryUseCase!
    private var registry: MockSavedEntryService!
    private var mockDB: MockDB!

    override func setUp() {
        super.setUp()
        registry = MockSavedEntryService()
        mockDB = MockDB()
        sut = DeleteEntryUseCase(entries: registry, db: mockDB)
    }

    override func tearDown() {
        sut = nil
        registry = nil
        mockDB = nil
        super.tearDown()
    }

    private func makeEntry(id: UUID = UUID(), sortIndex: Int = 0) -> SavedEntry {
        SavedEntry(
            id: id,
            name: "Entry",
            kind: .browse(BrowseEntry(url: URL(fileURLWithPath: "/tmp/x"), app: .default)),
            sortIndex: sortIndex
        )
    }

    // MARK: - Transaction boundary

    func test_execute_runsInsideOneTransaction() async throws {
        let id = UUID()
        registry.listAllResult = [makeEntry(id: id)]
        try await sut.execute(DeleteEntryRequest(id: id))
        XCTAssertEqual(mockDB.transactionCallCount, 1)
    }

    func test_execute_stagesReplaceAllEntriesOnce() async throws {
        let id = UUID()
        registry.listAllResult = [makeEntry(id: id)]
        try await sut.execute(DeleteEntryRequest(id: id))
        XCTAssertEqual(mockDB.tx.replaceAllEntriesCallCount, 1)
    }

    // MARK: - Read-before-write

    func test_execute_callsListAllOnce() async throws {
        let id = UUID()
        registry.listAllResult = [makeEntry(id: id)]
        try await sut.execute(DeleteEntryRequest(id: id))
        XCTAssertEqual(registry.listAllCallCount, 1)
    }

    // MARK: - Deletion logic

    func test_execute_removesEntryFromStagedCollection() async throws {
        let id = UUID()
        let other = makeEntry(sortIndex: 1)
        registry.listAllResult = [makeEntry(id: id, sortIndex: 0), other]
        try await sut.execute(DeleteEntryRequest(id: id))
        let staged = mockDB.tx.replacedEntries ?? []
        XCTAssertFalse(staged.contains { $0.id == id })
    }

    func test_execute_keepsOtherEntries() async throws {
        let id = UUID()
        let other = makeEntry(sortIndex: 1)
        registry.listAllResult = [makeEntry(id: id, sortIndex: 0), other]
        try await sut.execute(DeleteEntryRequest(id: id))
        let staged = mockDB.tx.replacedEntries ?? []
        XCTAssertTrue(staged.contains { $0.id == other.id })
    }

    // MARK: - Not-found error

    func test_execute_throwsItemNotFound_whenIDAbsent() async throws {
        registry.listAllResult = []
        do {
            try await sut.execute(DeleteEntryRequest(id: UUID()))
            XCTFail("Expected itemNotFound error")
        } catch OperationError.itemNotFound {
            // expected
        }
    }

    func test_execute_doesNotCallPerform_whenIDAbsent() async throws {
        registry.listAllResult = []
        do {
            try await sut.execute(DeleteEntryRequest(id: UUID()))
        } catch {}
        XCTAssertEqual(mockDB.transactionCallCount, 0)
    }
}
