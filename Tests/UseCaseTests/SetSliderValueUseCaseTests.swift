import XCTest
@testable import YourUsual

final class SetSliderValueUseCaseTests: XCTestCase {
    private var sut: SetSliderValueUseCase!
    private var mockEntries: MockSavedEntryService!
    private var mockDB: MockDB!
    private var mockDiagnostics: MockDiagnostics!

    override func setUp() {
        super.setUp()
        mockEntries = MockSavedEntryService()
        mockDB = MockDB()
        mockDiagnostics = MockDiagnostics()
        sut = SetSliderValueUseCase(entries: mockEntries, db: mockDB, diagnostics: mockDiagnostics)
    }

    override func tearDown() {
        sut = nil
        mockEntries = nil
        mockDB = nil
        mockDiagnostics = nil
        super.tearDown()
    }

    private struct StubError: Error {}

    private func slider(id: UUID, current: Double) -> SavedEntry {
        SavedEntry(
            id: id, name: "Volume",
            kind: .slider(SliderEntry(
                commandLine: "v <VALUE>", minValue: 0, maxValue: 100, step: 1, currentValue: current
            )),
            sortIndex: 0
        )
    }

    // MARK: - Read before transaction

    func testExecute_readsAllEntriesOnce() async throws {
        let id = UUID()
        mockEntries.listAllResult = [slider(id: id, current: 10)]
        try await sut.execute(SetSliderValueRequest(entryID: id, value: 40))
        XCTAssertEqual(mockEntries.listAllCallCount, 1)
    }

    // MARK: - Gerund transform

    func testExecute_appliesSliderValueTransformOnce() async throws {
        let id = UUID()
        mockEntries.listAllResult = [slider(id: id, current: 10)]
        try await sut.execute(SetSliderValueRequest(entryID: id, value: 40))
        XCTAssertEqual(mockEntries.editingSliderValueCallCount, 1)
    }

    func testExecute_passesTargetIDToTransform() async throws {
        let id = UUID()
        mockEntries.listAllResult = [slider(id: id, current: 10)]
        try await sut.execute(SetSliderValueRequest(entryID: id, value: 40))
        XCTAssertEqual(mockEntries.editingSliderValueID, id)
    }

    func testExecute_passesValueToTransform() async throws {
        let id = UUID()
        mockEntries.listAllResult = [slider(id: id, current: 10)]
        try await sut.execute(SetSliderValueRequest(entryID: id, value: 40))
        XCTAssertEqual(mockEntries.editingSliderValueValue, 40)
    }

    // MARK: - Commit

    func testExecute_opensExactlyOneTransaction() async throws {
        let id = UUID()
        mockEntries.listAllResult = [slider(id: id, current: 10)]
        try await sut.execute(SetSliderValueRequest(entryID: id, value: 40))
        XCTAssertEqual(mockDB.transactionCallCount, 1)
    }

    func testExecute_commitsViaReplaceAllEntries() async throws {
        let id = UUID()
        mockEntries.listAllResult = [slider(id: id, current: 10)]
        try await sut.execute(SetSliderValueRequest(entryID: id, value: 40))
        XCTAssertEqual(mockDB.tx.replaceAllEntriesCallCount, 1)
    }

    func testExecute_persistsTheUpdatedValue() async throws {
        let id = UUID()
        mockEntries.listAllResult = [slider(id: id, current: 10)]
        try await sut.execute(SetSliderValueRequest(entryID: id, value: 40))
        guard case .slider(let updated) = mockDB.tx.replacedEntries?.first?.kind else {
            return XCTFail("Expected a slider entry to be committed")
        }
        XCTAssertEqual(updated.currentValue, 40)
    }

    // MARK: - Best-effort persistence: failures are observable, not silently lost

    func testExecute_onPersistenceFailure_logsWarning() async {
        mockEntries.listAllError = StubError()
        do {
            try await sut.execute(SetSliderValueRequest(entryID: UUID(), value: 40))
            XCTFail("Expected the persistence failure to propagate")
        } catch {
            XCTAssertEqual(mockDiagnostics.warningCallCount, 1)
        }
    }

    func testExecute_onPersistenceFailure_rethrows() async {
        mockEntries.listAllError = StubError()
        do {
            try await sut.execute(SetSliderValueRequest(entryID: UUID(), value: 40))
            XCTFail("Expected the persistence failure to propagate so the caller's try? holds")
        } catch {
            XCTAssertTrue(error is StubError)
        }
    }

    func testExecute_onSuccess_doesNotLog() async throws {
        let id = UUID()
        mockEntries.listAllResult = [slider(id: id, current: 10)]
        try await sut.execute(SetSliderValueRequest(entryID: id, value: 40))
        XCTAssertEqual(mockDiagnostics.warningCallCount, 0)
    }
}
