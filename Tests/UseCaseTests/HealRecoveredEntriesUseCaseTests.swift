import XCTest
@testable import YourUsual

final class HealRecoveredEntriesUseCaseTests: XCTestCase {
    private var sut: HealRecoveredEntriesUseCase!
    private var entries: MockSavedEntryService!
    private var mockDB: MockDB!

    override func setUp() {
        super.setUp()
        entries = MockSavedEntryService()
        mockDB = MockDB()
        sut = HealRecoveredEntriesUseCase(entries: entries, db: mockDB)
    }

    override func tearDown() {
        sut = nil
        entries = nil
        mockDB = nil
        super.tearDown()
    }

    private func entry(_ name: String, isRecovered: Bool) -> SavedEntry {
        SavedEntry(
            name: name,
            kind: .browse(BrowseEntry(url: URL(fileURLWithPath: "/tmp/\(name)"), app: .default)),
            sortIndex: 0,
            isRecovered: isRecovered
        )
    }

    // MARK: - Recovered entries present → heal

    func test_execute_withRecovered_persistsTheCollectionOnce() async throws {
        entries.listAllResult = [entry("broken", isRecovered: true), entry("ok", isRecovered: false)]
        _ = try await sut.execute(HealRecoveredEntriesRequest())
        XCTAssertEqual(mockDB.tx.replaceAllEntriesCallCount, 1)
    }

    func test_execute_withRecovered_returnsResetCount() async throws {
        entries.listAllResult = [
            entry("broken1", isRecovered: true),
            entry("broken2", isRecovered: true),
            entry("ok", isRecovered: false)
        ]
        let count = try await sut.execute(HealRecoveredEntriesRequest())
        XCTAssertEqual(count, 2)
    }

    func test_execute_withRecovered_persistsWholeCollectionNotJustRecovered() async throws {
        entries.listAllResult = [entry("broken", isRecovered: true), entry("ok", isRecovered: false)]
        _ = try await sut.execute(HealRecoveredEntriesRequest())
        XCTAssertEqual(mockDB.tx.replacedEntries?.count, 2)
    }

    // MARK: - No recovered entries → no-op

    func test_execute_noRecovered_doesNotOpenTransaction() async throws {
        entries.listAllResult = [entry("ok", isRecovered: false)]
        _ = try await sut.execute(HealRecoveredEntriesRequest())
        XCTAssertEqual(mockDB.transactionCallCount, 0)
    }

    func test_execute_noRecovered_returnsZero() async throws {
        entries.listAllResult = [entry("ok", isRecovered: false)]
        let count = try await sut.execute(HealRecoveredEntriesRequest())
        XCTAssertEqual(count, 0)
    }

    func test_execute_emptyRegistry_returnsZero() async throws {
        entries.listAllResult = []
        let count = try await sut.execute(HealRecoveredEntriesRequest())
        XCTAssertEqual(count, 0)
    }
}
