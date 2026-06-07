import XCTest
@testable import YourUsual

final class RunStreamingEntryUseCaseTests: XCTestCase {
    private var sut: RunStreamingEntryUseCase!
    private var mockCommand: MockCommandRunnerService!
    private var mockAppleScript: MockAppleScriptRunnerService!
    private var mockNotification: MockNotificationService!
    private var mockHistory: MockRunHistoryService!
    private var mockDB: MockDB!
    private var mockDiagnostics: MockDiagnostics!

    override func setUp() {
        super.setUp()
        mockCommand = MockCommandRunnerService()
        mockAppleScript = MockAppleScriptRunnerService()
        mockNotification = MockNotificationService()
        mockHistory = MockRunHistoryService()
        mockDB = MockDB()
        mockDiagnostics = MockDiagnostics()
        sut = RunStreamingEntryUseCase(
            command: mockCommand,
            appleScript: mockAppleScript,
            notification: mockNotification,
            history: mockHistory,
            db: mockDB,
            diagnostics: mockDiagnostics,
            outputSettings: MockCommandOutputSettingsService(),
            currentDirectory: MockCurrentDirectoryService(),
            resolver: MockWorkingDirectoryResolver()
        )
    }

    override func tearDown() {
        sut = nil
        mockCommand = nil
        mockAppleScript = nil
        mockNotification = nil
        mockHistory = nil
        mockDB = nil
        mockDiagnostics = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func backgroundRequest(id: UUID = UUID(), name: String = "List") -> RunStreamingEntryRequest {
        RunStreamingEntryRequest(entry: SavedEntryResponse(
            id: id,
            name: name,
            kind: .command(CommandPayload(commandLine: "echo hi", workingDirectory: nil, sink: .background))
        ))
    }

    private func terminalRequest() -> RunStreamingEntryRequest {
        RunStreamingEntryRequest(entry: SavedEntryResponse(
            id: UUID(),
            name: "Top",
            kind: .command(CommandPayload(commandLine: "top", workingDirectory: nil, sink: .terminal))
        ))
    }

    private func appleScriptRequest(name: String = "Greet") -> RunStreamingEntryRequest {
        RunStreamingEntryRequest(entry: SavedEntryResponse(
            id: UUID(),
            name: name,
            kind: .appleScript(AppleScriptPayload(source: "return 1"))
        ))
    }

    private func drain(_ stream: AsyncThrowingStream<CommandOutputResponse, Error>) async -> [CommandOutputResponse] {
        var collected: [CommandOutputResponse] = []
        do {
            for try await chunk in stream { collected.append(chunk) }
        } catch {
            XCTFail("unexpected stream error: \(error)")
        }
        return collected
    }

    // MARK: - Streaming

    func testExecute_yieldsMappedOutputChunks() async throws {
        mockCommand.streamEvents = [.stdout("a"), .stderr("b"), .exit(0)]
        let chunks = await drain(try await sut.execute(backgroundRequest()))
        XCTAssertEqual(chunks, [.stdout("a"), .stderr("b"), .exit(code: 0, succeeded: true)])
    }

    // MARK: - Transaction boundary — history clear

    func testExecute_clearsPriorHistoryInsideTransaction() async throws {
        mockCommand.streamEvents = [.exit(0)]
        let id = UUID()
        _ = await drain(try await sut.execute(backgroundRequest(id: id)))
        XCTAssertEqual(mockDB.tx.deleteAllRunsForEntryCallCount, 1)
    }

    func testExecute_clearsPriorHistoryForCorrectEntryID() async throws {
        mockCommand.streamEvents = [.exit(0)]
        let id = UUID()
        _ = await drain(try await sut.execute(backgroundRequest(id: id)))
        XCTAssertEqual(mockDB.tx.deleteAllRunsForEntryID, id)
    }

    // MARK: - Transaction boundary — history register

    func testExecute_persistsExactlyOneRecordOnExit() async throws {
        mockCommand.streamEvents = [.stdout("x"), .exit(0)]
        _ = await drain(try await sut.execute(backgroundRequest()))
        XCTAssertEqual(mockDB.tx.registerRunCallCount, 1)
    }

    func testExecute_delegatesRecordAssemblyToHistoryService() async throws {
        mockCommand.streamEvents = [.exit(0)]
        _ = await drain(try await sut.execute(backgroundRequest()))
        XCTAssertEqual(mockHistory.makeRunRecordCallCount, 1)
    }

    func testExecute_persistedRecord_hasCorrectEntryID() async throws {
        mockCommand.streamEvents = [.exit(0)]
        let id = UUID()
        _ = await drain(try await sut.execute(backgroundRequest(id: id)))
        XCTAssertEqual(mockDB.tx.registeredRun?.entryID, id)
    }

    // MARK: - Best-effort persistence is observable, not silent

    func testExecute_persistenceFailure_stillCompletesTheRun() async throws {
        mockDB.shouldThrow = true
        mockCommand.streamEvents = [.stdout("x"), .exit(0)]
        let chunks = await drain(try await sut.execute(backgroundRequest()))
        XCTAssertEqual(chunks, [.stdout("x"), .exit(code: 0, succeeded: true)])
    }

    func testExecute_persistenceFailure_logsDiagnostic() async throws {
        mockDB.shouldThrow = true
        mockCommand.streamEvents = [.exit(0)]
        _ = await drain(try await sut.execute(backgroundRequest()))
        XCTAssertGreaterThan(mockDiagnostics.warningCallCount, 0)
    }

    func testExecute_persistenceSucceeds_logsNoDiagnostic() async throws {
        mockCommand.streamEvents = [.exit(0)]
        _ = await drain(try await sut.execute(backgroundRequest()))
        XCTAssertEqual(mockDiagnostics.warningCallCount, 0)
    }

    // MARK: - Notification

    func testExecute_notifiesOnCompletion() async throws {
        mockCommand.streamEvents = [.exit(2)]
        _ = await drain(try await sut.execute(backgroundRequest(name: "Build")))
        XCTAssertEqual(mockNotification.notifyIfNeededCallCount, 1)
        XCTAssertEqual(mockNotification.notifiedName, "Build")
    }

    func testExecute_nonZeroExit_reportsNotSucceeded() async throws {
        mockCommand.streamEvents = [.exit(1)]
        let chunks = await drain(try await sut.execute(backgroundRequest()))
        XCTAssertEqual(chunks, [.exit(code: 1, succeeded: false)])
    }

    // MARK: - Failure path

    func testExecute_streamError_notifiesFailure() async throws {
        mockCommand.streamError = OperationError.commandFailed(exitCode: -1, stderr: "spawn failed")
        var threw = false
        do {
            for try await _ in try await sut.execute(backgroundRequest(name: "Boom")) {}
        } catch {
            threw = true
        }
        XCTAssertTrue(threw)
        XCTAssertEqual(mockNotification.notifyFailureCallCount, 1)
    }

    // Clear + register are atomic on `.exit`, so a run that fails to spawn (never
    // reaches `.exit`) leaves the prior history record intact rather than wiping it.
    func testExecute_spawnFailure_doesNotClearHistory() async throws {
        mockCommand.streamError = OperationError.commandFailed(exitCode: -1, stderr: "spawn failed")
        do {
            for try await _ in try await sut.execute(backgroundRequest()) {}
        } catch {}
        XCTAssertEqual(mockDB.tx.deleteAllRunsForEntryCallCount, 0)
    }

    // MARK: - Open entries are misrouted here — fail loudly, never stream or persist

    // A `.terminal` command resolves to `.open`, so reaching the run-and-stream path is
    // a routing bug. It must throw rather than finish an empty stream silently.
    func testExecute_terminalSink_throwsMisroutedEntry() async throws {
        do {
            _ = try await sut.execute(terminalRequest())
            XCTFail("Expected misroutedEntry to be thrown")
        } catch {
            XCTAssertEqual(error as? OperationError,
                           .misroutedEntry(reason: "Top is not a run-and-stream entry"))
        }
    }

    func testExecute_terminalSink_doesNotStreamOrPersist() async throws {
        _ = try? await sut.execute(terminalRequest())
        XCTAssertEqual(mockCommand.streamCallCount, 0)
        XCTAssertEqual(mockDB.tx.registerRunCallCount, 0)
    }

    // MARK: - AppleScript stream

    func testExecute_appleScript_success_yieldsResultThenExit() async throws {
        mockAppleScript.runResult = "hello"
        let chunks = await drain(try await sut.execute(appleScriptRequest()))
        XCTAssertEqual(chunks, [.stdout("hello"), .exit(code: 0, succeeded: true)])
    }

    func testExecute_appleScript_success_notifiesCompletion() async throws {
        mockAppleScript.runResult = "hello"
        _ = await drain(try await sut.execute(appleScriptRequest()))
        XCTAssertEqual(mockNotification.notifyCompletionCallCount, 1)
    }

    // Failure unifies with the background path: it throws via finish(throwing:),
    // never a synthesized .exit(succeeded: false).
    func testExecute_appleScript_failure_throws() async throws {
        mockAppleScript.error = OperationError.applescriptFailed(reason: "boom")
        var threw = false
        do {
            for try await _ in try await sut.execute(appleScriptRequest()) {}
        } catch {
            threw = true
        }
        XCTAssertTrue(threw)
    }

    func testExecute_appleScript_failure_notifiesFailure() async throws {
        mockAppleScript.error = OperationError.applescriptFailed(reason: "boom")
        do {
            for try await _ in try await sut.execute(appleScriptRequest()) {}
        } catch {}
        XCTAssertEqual(mockNotification.notifyFailureCallCount, 1)
    }
}
