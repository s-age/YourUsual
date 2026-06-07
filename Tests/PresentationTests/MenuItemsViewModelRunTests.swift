import XCTest
@testable import YourUsual

/// Covers the background-command run/output/delete behavior of MenuItemsViewModel,
/// split from MenuItemsViewModelTests to stay under the per-file line limit.
@MainActor
final class MenuItemsViewModelRunTests: XCTestCase {
    private var mockFetch: MockReadEntriesUseCase!
    private var mockReadCategories: MockReadCategoriesUseCase!
    private var mockOpenEntry: MockOpenEntryUseCase!
    private var mockRunStreamingEntry: MockRunStreamingEntryUseCase!
    private var mockDeleteHistory: MockDeleteHistoryUseCase!
    private var registry: RegistryViewModel!
    private var sut: MenuItemsViewModel!

    override func setUp() {
        super.setUp()
        mockFetch = MockReadEntriesUseCase()
        mockReadCategories = MockReadCategoriesUseCase()
        mockOpenEntry = MockOpenEntryUseCase()
        mockRunStreamingEntry = MockRunStreamingEntryUseCase()
        mockDeleteHistory = MockDeleteHistoryUseCase()
        registry = RegistryViewModel(readEntries: mockFetch, readCategories: mockReadCategories)
        sut = MenuItemsViewModel(
            registry: registry,
            openEntry: mockOpenEntry,
            runStreamingEntry: mockRunStreamingEntry,
            deleteHistory: mockDeleteHistory,
            readLaunchAtLogin: MockReadLaunchAtLoginUseCase(),
            setLaunchAtLogin: MockSetLaunchAtLoginUseCase(),
            readCurrentDirectory: MockReadCurrentDirectoryUseCase(),
            appIcons: makeTestAppIconCache()
        )
    }

    override func tearDown() {
        sut = nil
        registry = nil
        mockFetch = nil
        mockReadCategories = nil
        mockOpenEntry = nil
        mockRunStreamingEntry = nil
        mockDeleteHistory = nil
        super.tearDown()
    }

    private func commandItem(id: UUID = UUID()) -> SavedEntryResponse {
        SavedEntryResponse(
            id: id,
            name: "List",
            kind: .command(CommandPayload(commandLine: "/bin/ls", workingDirectory: nil, sink: .background))
        )
    }

    /// `run` is fire-and-forget (stored task); yield until the run settles.
    private func waitUntilSettled(_ id: UUID) async {
        for _ in 0..<1000 where sut.isRunning(id) { await Task.yield() }
    }

    // MARK: - run()

    func testRun_accumulatesStreamedStdout() async {
        let id = UUID()
        mockRunStreamingEntry.events = [.stdout("hel"), .stdout("lo"), .exit(code: 0, succeeded: true)]
        sut.run(commandItem(id: id))
        await waitUntilSettled(id)
        XCTAssertEqual(sut.output(for: id)?.stdout, "hello")
    }

    func testRun_recordsExitCode() async {
        let id = UUID()
        mockRunStreamingEntry.events = [.exit(code: 3, succeeded: false)]
        sut.run(commandItem(id: id))
        await waitUntilSettled(id)
        XCTAssertEqual(sut.output(for: id)?.completion, .finished(code: 3, succeeded: false))
    }

    func testRun_clearsRunningFlagOnCompletion() async {
        let id = UUID()
        mockRunStreamingEntry.events = [.exit(code: 0, succeeded: true)]
        sut.run(commandItem(id: id))
        await waitUntilSettled(id)
        XCTAssertFalse(sut.isRunning(id))
    }

    func testRun_passesEntryToUseCase() async {
        let id = UUID()
        mockRunStreamingEntry.events = [.exit(code: 0, succeeded: true)]
        sut.run(commandItem(id: id))
        await waitUntilSettled(id)
        XCTAssertEqual(mockRunStreamingEntry.receivedRequest?.entry.id, id)
    }

    func testRun_capsStdoutBufferToMaxBytes() async {
        let id = UUID()
        // Emit far more than the cap to force trimming; the live buffer must stay
        // bounded so a chatty command can't grow memory unboundedly.
        let chunk = String(repeating: "a", count: 50_000)
        let events: [CommandOutputResponse] = (0..<10).map { _ in .stdout(chunk) }
            + [.exit(code: 0, succeeded: true)]
        mockRunStreamingEntry.events = events
        sut.run(commandItem(id: id))
        await waitUntilSettled(id)
        let stdout = sut.output(for: id)?.stdout ?? ""
        XCTAssertLessThanOrEqual(stdout.utf8.count, CommandOutput.maxOutputBytes)
    }

    func testRun_capsMultibyteStdoutBufferToMaxBytes() async {
        let id = UUID()
        // Non-ASCII (box-drawing "─" is 3 UTF-8 bytes): the byte-budget trim must keep
        // the buffer under the byte cap. A Character-count bound would keep ~3× the
        // bytes and overshoot — this guards the byte-bounded tail walk.
        let chunk = String(repeating: "─", count: 50_000)
        let events: [CommandOutputResponse] = (0..<10).map { _ in .stdout(chunk) }
            + [.exit(code: 0, succeeded: true)]
        mockRunStreamingEntry.events = events
        sut.run(commandItem(id: id))
        await waitUntilSettled(id)
        let stdout = sut.output(for: id)?.stdout ?? ""
        XCTAssertLessThanOrEqual(stdout.utf8.count, CommandOutput.maxOutputBytes)
    }

    // MARK: - deleteResult()

    func testDeleteResult_clearsDisplayedOutput() async {
        let id = UUID()
        mockRunStreamingEntry.events = [.stdout("x"), .exit(code: 0, succeeded: true)]
        sut.run(commandItem(id: id))
        await waitUntilSettled(id)

        sut.deleteResult(commandItem(id: id))

        XCTAssertNil(sut.output(for: id))
    }

    /// Regression: deleting a live run and immediately re-running the same id must not
    /// let the first (now-cancelled) run's `defer` clear the slot the new run claimed.
    /// Without the per-run generation guard, the late-resuming first task wiped the new
    /// task's `runTasks[id]`, so `isRunning` falsely reported the new run as stopped.
    func testDeleteThenImmediateRerun_keepsNewRunRegistered() async {
        let id = UUID()
        mockRunStreamingEntry.keepOpen = true               // first run suspends mid-stream
        mockRunStreamingEntry.events = [.stdout("x")]
        sut.run(commandItem(id: id))
        for _ in 0..<50 { await Task.yield() }              // let run A park on the open stream

        sut.deleteResult(commandItem(id: id))               // cancels run A, frees the slot
        sut.run(commandItem(id: id))                        // run B claims the slot synchronously

        // Drive run A's cancelled task to resume and execute its defer.
        for _ in 0..<1000 { await Task.yield() }

        XCTAssertTrue(sut.isRunning(id))                    // run B must still be registered

        sut.deleteResult(commandItem(id: id))               // clean up the hanging run B
    }

    func testDeleteResult_deletesEntryHistory() async {
        let id = UUID()
        sut.deleteResult(commandItem(id: id))
        // The delete is dispatched on a detached task — yield until it lands.
        for _ in 0..<1000 where mockDeleteHistory.callCount == 0 { await Task.yield() }
        if case .entry(let scopedID) = mockDeleteHistory.receivedScope {
            XCTAssertEqual(scopedID, id)
        } else {
            XCTFail("Expected .entry(\(id)) scope, got \(String(describing: mockDeleteHistory.receivedScope))")
        }
    }
}
