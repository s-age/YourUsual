import XCTest
@testable import YourUsual

final class RunSliderUseCaseTests: XCTestCase {
    private var sut: RunSliderUseCase!
    private var mockCommand: MockCommandRunnerService!
    private var mockCurrentDirectory: MockCurrentDirectoryService!
    private var mockResolver: MockWorkingDirectoryResolver!

    override func setUp() {
        super.setUp()
        mockCommand = MockCommandRunnerService()
        mockCurrentDirectory = MockCurrentDirectoryService()
        mockResolver = MockWorkingDirectoryResolver()
        sut = RunSliderUseCase(
            command: mockCommand,
            currentDirectory: mockCurrentDirectory,
            resolver: mockResolver
        )
    }

    override func tearDown() {
        sut = nil
        mockCommand = nil
        mockCurrentDirectory = nil
        mockResolver = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func sliderRequest(
        commandLine: String = "set volume output volume <VALUE>",
        step: Double = 1,
        value: Double = 60
    ) -> RunSliderRequest {
        RunSliderRequest(
            entry: SavedEntryResponse(
                id: UUID(),
                name: "Volume",
                kind: .slider(SliderPayload(
                    commandLine: commandLine, minValue: 0, maxValue: 100, step: step, currentValue: 0
                ))
            ),
            value: value
        )
    }

    private func commandRequest() -> RunSliderRequest {
        RunSliderRequest(
            entry: SavedEntryResponse(
                id: UUID(),
                name: "List",
                kind: .command(CommandPayload(commandLine: "ls", workingDirectory: nil, sink: .background))
            ),
            value: 1
        )
    }

    // MARK: - Runs the command

    func testExecute_streamsTheCommandOnce() async throws {
        try await sut.execute(sliderRequest())
        XCTAssertEqual(mockCommand.streamCallCount, 1)
    }

    func testExecute_substitutesValueIntoCommandLine() async throws {
        try await sut.execute(sliderRequest(value: 60))
        XCTAssertEqual(mockCommand.streamedEntry?.line, "set volume output volume 60")
    }

    func testExecute_formatsValuePerStep() async throws {
        try await sut.execute(sliderRequest(commandLine: "x <VALUE>", step: 0.1, value: 0.5))
        XCTAssertEqual(mockCommand.streamedEntry?.line, "x 0.5")
    }

    func testExecute_runsInBackground() async throws {
        try await sut.execute(sliderRequest())
        XCTAssertEqual(mockCommand.streamedEntry?.sink, .background)
    }

    func testExecute_runsInResolvedCurrentDirectory() async throws {
        mockResolver.resolveResult = URL(fileURLWithPath: "/tmp/work")
        try await sut.execute(sliderRequest())
        XCTAssertEqual(mockCommand.streamedCurrentDirectory, URL(fileURLWithPath: "/tmp/work"))
    }

    func testExecute_setsWorkingDirectoryToResolvedCurrentDirectory() async throws {
        mockResolver.resolveResult = URL(fileURLWithPath: "/tmp/work")
        try await sut.execute(sliderRequest())
        XCTAssertEqual(mockCommand.streamedEntry?.workingDirectory, "/tmp/work")
    }

    // MARK: - No notification / no history
    //
    // `RunSliderUseCase` structurally holds neither a `NotificationService` nor a
    // `RunHistoryService` (unlike `RunStreamingEntryUseCase`), so "never notifies / never
    // records history" is guaranteed by construction — there is no dependency to call. The
    // stream is drained for its side effect only; output and exit code are discarded.

    func testExecute_drainsStreamWithoutThrowing_evenOnNonZeroExit() async throws {
        mockCommand.streamEvents = [.stdout("noise"), .exit(1)]
        try await sut.execute(sliderRequest())
        XCTAssertEqual(mockCommand.streamCallCount, 1)
    }

    // MARK: - Misrouting

    func testExecute_nonSliderEntry_throwsMisroutedEntry() async throws {
        do {
            try await sut.execute(commandRequest())
            XCTFail("Expected misroutedEntry to be thrown")
        } catch {
            XCTAssertEqual(error as? OperationError, .misroutedEntry(reason: "List is not a slider"))
        }
    }

    func testExecute_nonSliderEntry_doesNotStream() async throws {
        try? await sut.execute(commandRequest())
        XCTAssertEqual(mockCommand.streamCallCount, 0)
    }
}
