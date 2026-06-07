import XCTest
@testable import YourUsual

final class RegisterEntryUseCaseTests: XCTestCase {
    private var sut: RegisterEntryUseCase!
    private var registry: MockSavedEntryService!
    private var mockDB: MockDB!

    override func setUp() {
        super.setUp()
        registry = MockSavedEntryService()
        mockDB = MockDB()
        sut = RegisterEntryUseCase(entries: registry, db: mockDB)
    }

    override func tearDown() {
        sut = nil
        registry = nil
        mockDB = nil
        super.tearDown()
    }

    private func validRequest() -> RegisterEntryRequest {
        RegisterEntryRequest(
            name: "Notes",
            kind: .browse(BrowsePayload(path: "/tmp/notes.txt", app: .default))
        )
    }

    // MARK: - Transaction boundary

    func test_execute_validRequest_runsInsideOneTransaction() async throws {
        _ = try await sut.execute(validRequest())
        XCTAssertEqual(mockDB.transactionCallCount, 1)
    }

    func test_execute_validRequest_stagesReplaceAllEntriesOnce() async throws {
        _ = try await sut.execute(validRequest())
        XCTAssertEqual(mockDB.tx.replaceAllEntriesCallCount, 1)
    }

    // MARK: - Read-before-write

    func test_execute_validRequest_callsListAllOnce() async throws {
        _ = try await sut.execute(validRequest())
        XCTAssertEqual(registry.listAllCallCount, 1)
    }

    // MARK: - Item construction

    func test_execute_validRequest_appendsNewEntryToExisting() async throws {
        let existing = SavedEntry(
            name: "Old",
            kind: .browse(BrowseEntry(url: URL(fileURLWithPath: "/tmp/old"), app: .default)),
            sortIndex: 0
        )
        registry.listAllResult = [existing]
        _ = try await sut.execute(validRequest())
        XCTAssertEqual(mockDB.tx.replacedEntries?.count, 2)
    }

    func test_execute_validRequest_assignsNextSortIndex() async throws {
        let existing = SavedEntry(
            name: "Old",
            kind: .browse(BrowseEntry(url: URL(fileURLWithPath: "/tmp/old"), app: .default)),
            sortIndex: 5
        )
        registry.listAllResult = [existing]
        _ = try await sut.execute(validRequest())
        let newItem = mockDB.tx.replacedEntries?.last
        XCTAssertEqual(newItem?.sortIndex, 6)
    }

    func test_execute_validRequest_usesDefaultCategoryWhenNil() async throws {
        _ = try await sut.execute(validRequest())
        let newItem = mockDB.tx.replacedEntries?.last
        XCTAssertEqual(newItem?.categoryID, EntryCategory.defaultID)
    }

    func test_execute_validRequest_usesCategoryIDFromRequest() async throws {
        let catID = UUID()
        let request = RegisterEntryRequest(
            name: "Notes",
            kind: .browse(BrowsePayload(path: "/tmp/notes.txt", app: .default)),
            categoryID: catID
        )
        _ = try await sut.execute(request)
        let newItem = mockDB.tx.replacedEntries?.last
        XCTAssertEqual(newItem?.categoryID, catID)
    }

    func test_execute_validRequest_mapsBrowseKind() async throws {
        _ = try await sut.execute(validRequest())
        let newItem = mockDB.tx.replacedEntries?.last
        XCTAssertEqual(
            newItem?.kind,
            .browse(BrowseEntry(url: URL(fileURLWithPath: "/tmp/notes.txt"), app: .default))
        )
    }

    func test_execute_commandRequest_mapsCommandKind() async throws {
        let request = RegisterEntryRequest(
            name: "List",
            kind: .command(CommandPayload(commandLine: "/bin/ls -la", workingDirectory: nil, sink: .background))
        )
        _ = try await sut.execute(request)
        let newItem = mockDB.tx.replacedEntries?.last
        XCTAssertEqual(
            newItem?.kind,
            .command(CommandEntry(line: "/bin/ls -la", workingDirectory: nil, sink: .background))
        )
    }

    // MARK: - Response

    func test_execute_validRequest_returnsResponseWithNewEntryName() async throws {
        let response = try await sut.execute(validRequest())
        XCTAssertEqual(response.name, "Notes")
    }

    func test_execute_validRequest_returnsResponseWithNewEntryID() async throws {
        let response = try await sut.execute(validRequest())
        // The new item's id is stable between listAll and the response.
        let staged = mockDB.tx.replacedEntries?.last
        XCTAssertEqual(response.id, staged?.id)
    }

    // MARK: - Validation failure

    // Validation is a cross-cutting concern of `ValidationAsyncUseCaseDecorator`
    // (wired in the DI layer), not of the bare use case. The request-level
    // rules themselves are covered by `RegisterEntryRequestTests`.
    private func validatingSUT() -> ValidationAsyncUseCaseDecorator<RegisterEntryRequest, SavedEntryResponse> {
        ValidationAsyncUseCaseDecorator(decoratee: sut)
    }

    func test_execute_invalidRequest_doesNotCallListAll() async throws {
        let request = RegisterEntryRequest(
            name: "",
            kind: .browse(BrowsePayload(path: "/tmp/x", app: .default))
        )
        do {
            _ = try await validatingSUT().execute(request)
            XCTFail("Expected validation to throw")
        } catch {
            XCTAssertEqual(registry.listAllCallCount, 0)
        }
    }

    func test_execute_invalidRequest_doesNotCallPerform() async throws {
        let request = RegisterEntryRequest(
            name: "",
            kind: .browse(BrowsePayload(path: "/tmp/x", app: .default))
        )
        do {
            _ = try await validatingSUT().execute(request)
            XCTFail("Expected validation to throw")
        } catch {
            XCTAssertEqual(mockDB.transactionCallCount, 0)
        }
    }

    func test_execute_invalidRequest_throwsValidationError() async throws {
        let request = RegisterEntryRequest(
            name: "",
            kind: .browse(BrowsePayload(path: "/tmp/x", app: .default))
        )
        do {
            _ = try await validatingSUT().execute(request)
            XCTFail("Expected validation to throw")
        } catch {
            guard case ValidationError.emptyField = error else {
                return XCTFail("Expected ValidationError.emptyField, got \(error)")
            }
        }
    }
}
