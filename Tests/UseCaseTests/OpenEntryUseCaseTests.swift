import XCTest
@testable import YourUsual

final class OpenEntryUseCaseTests: XCTestCase {
    private var sut: OpenEntryUseCase!
    private var mockBrowse: MockBrowseLauncherService!
    private var mockCommand: MockCommandRunnerService!
    private var mockNotification: MockNotificationService!
    private var mockTerminalSettings: MockTerminalSettingsService!
    private var mockCurrentDirectory: MockCurrentDirectoryService!
    private var mockResolver: MockWorkingDirectoryResolver!

    override func setUp() {
        super.setUp()
        mockBrowse = MockBrowseLauncherService()
        mockCommand = MockCommandRunnerService()
        mockNotification = MockNotificationService()
        mockTerminalSettings = MockTerminalSettingsService()
        mockCurrentDirectory = MockCurrentDirectoryService()
        mockResolver = MockWorkingDirectoryResolver()
        sut = OpenEntryUseCase(
            browse: mockBrowse,
            command: mockCommand,
            notification: mockNotification,
            terminalSettings: mockTerminalSettings,
            currentDirectory: mockCurrentDirectory,
            resolver: mockResolver
        )
    }

    override func tearDown() {
        sut = nil
        mockBrowse = nil
        mockCommand = nil
        mockNotification = nil
        mockTerminalSettings = nil
        mockCurrentDirectory = nil
        mockResolver = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeBrowseRequest(
        id: UUID = UUID(),
        name: String = "Notes"
    ) -> OpenEntryRequest {
        OpenEntryRequest(entry: SavedEntryResponse(
            id: id,
            name: name,
            kind: .browse(BrowsePayload(path: "/tmp/notes.txt", app: .default))
        ))
    }

    private func makeTerminalCommandRequest(
        id: UUID = UUID(),
        name: String = "Top",
        workingDirectory: String? = nil
    ) -> OpenEntryRequest {
        OpenEntryRequest(entry: SavedEntryResponse(
            id: id,
            name: name,
            kind: .command(CommandPayload(commandLine: "top", workingDirectory: workingDirectory, sink: .terminal))
        ))
    }

    private func makeAppleScriptRequest(name: String = "Greet") -> OpenEntryRequest {
        OpenEntryRequest(entry: SavedEntryResponse(
            id: UUID(),
            name: name,
            kind: .appleScript(AppleScriptPayload(source: "return 1"))
        ))
    }

    private func makeBackgroundCommandRequest(
        id: UUID = UUID(),
        name: String = "Build"
    ) -> OpenEntryRequest {
        OpenEntryRequest(entry: SavedEntryResponse(
            id: id,
            name: name,
            kind: .command(CommandPayload(commandLine: "make", workingDirectory: nil, sink: .background))
        ))
    }

    // MARK: - .command (terminal handoff)

    func testExecute_command_performsOnce() async throws {
        try await sut.execute(makeTerminalCommandRequest())
        XCTAssertEqual(mockCommand.performCallCount, 1)
    }

    // The UseCase resolves the global terminal preference through TerminalSettingsService
    // and hands it to the runner (the runner no longer reads the settings store itself).
    func testExecute_command_passesResolvedTerminalPreferenceToRunner() async throws {
        mockTerminalSettings.currentResult =
            TerminalPreference(selection: .known(.iterm), launchMode: .reuse)
        try await sut.execute(makeTerminalCommandRequest())
        XCTAssertEqual(mockCommand.performedPreference,
                       TerminalPreference(selection: .known(.iterm), launchMode: .reuse))
    }

    // The terminal owns its own output, so the open path neither notifies nor
    // records history for a successful command run.
    func testExecute_command_doesNotNotifyOnSuccess() async throws {
        try await sut.execute(makeTerminalCommandRequest())
        XCTAssertEqual(mockNotification.notifyIfNeededCallCount, 0)
    }

    func testExecute_command_doesNotNotifyFailureOnSuccess() async throws {
        try await sut.execute(makeTerminalCommandRequest())
        XCTAssertEqual(mockNotification.notifyFailureCallCount, 0)
    }

    // MARK: - current directory

    // The global current directory is resolved through WorkingDirectoryResolver and
    // handed to the runner (exported as YOUR_USUAL_CURRENT_DIRECTORY).
    func testExecute_command_passesResolvedCurrentDirectoryToRunner() async throws {
        mockResolver.resolveResult = URL(fileURLWithPath: "/work/dir")
        try await sut.execute(makeTerminalCommandRequest())
        XCTAssertEqual(mockCommand.performedCurrentDirectory, URL(fileURLWithPath: "/work/dir"))
    }

    // A `<WORKING_DIRECTORY>` working-directory sentinel is substituted with the resolved
    // current directory before the command runs.
    func testExecute_command_sentinelWorkingDirectory_resolvedToCurrentDirectory() async throws {
        mockResolver.resolveResult = URL(fileURLWithPath: "/work/dir")
        let request = makeTerminalCommandRequest(workingDirectory: WorkingDirectoryToken.current)
        try await sut.execute(request)
        XCTAssertEqual(mockCommand.performedEntry?.workingDirectory, "/work/dir")
    }

    // A fixed working directory is left untouched (no sentinel substitution).
    func testExecute_command_fixedWorkingDirectory_isUnchanged() async throws {
        mockResolver.resolveResult = URL(fileURLWithPath: "/work/dir")
        let request = makeTerminalCommandRequest(workingDirectory: "/fixed/path")
        try await sut.execute(request)
        XCTAssertEqual(mockCommand.performedEntry?.workingDirectory, "/fixed/path")
    }

    // MARK: - command.perform throws — notify + propagate

    func testExecute_commandPerformThrows_propagatesError() async throws {
        mockCommand.error = OperationError.terminalLaunchFailed(reason: "nope")
        do {
            try await sut.execute(makeTerminalCommandRequest())
            XCTFail("Expected error to propagate")
        } catch {
            XCTAssertNotNil(error as? OperationError)
        }
    }

    func testExecute_commandPerformThrows_notifiesFailure() async throws {
        mockCommand.error = OperationError.terminalLaunchFailed(reason: "nope")
        try? await sut.execute(makeTerminalCommandRequest())
        XCTAssertEqual(mockNotification.notifyFailureCallCount, 1)
    }

    // MARK: - .browse

    func testExecute_browse_launchesOnce() async throws {
        try await sut.execute(makeBrowseRequest())
        XCTAssertEqual(mockBrowse.launchCallCount, 1)
    }

    // MARK: - Run-and-stream kinds are misrouted here — fail loudly, never run them

    // A background command resolves to run-and-stream; arriving on the open path is a
    // routing bug. It must throw, not run in a terminal.
    func testExecute_backgroundCommand_throwsMisroutedEntry() async throws {
        do {
            try await sut.execute(makeBackgroundCommandRequest())
            XCTFail("Expected misroutedEntry to be thrown")
        } catch {
            XCTAssertEqual(error as? OperationError,
                           .misroutedEntry(reason: "Build is not an open entry"))
        }
    }

    func testExecute_backgroundCommand_doesNotPerformInTerminal() async throws {
        try? await sut.execute(makeBackgroundCommandRequest())
        XCTAssertEqual(mockCommand.performCallCount, 0)
    }

    // AppleScript resolves to run-and-stream, so reaching the open path is a misroute.
    func testExecute_appleScript_throwsMisroutedEntry() async throws {
        do {
            try await sut.execute(makeAppleScriptRequest(name: "Greet"))
            XCTFail("Expected misroutedEntry to be thrown")
        } catch {
            XCTAssertEqual(error as? OperationError,
                           .misroutedEntry(reason: "Greet is not an open entry"))
        }
    }
}
