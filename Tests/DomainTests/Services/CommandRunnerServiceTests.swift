import XCTest
@testable import YourUsual

final class CommandRunnerServiceTests: XCTestCase {
    private static let currentDir = URL(fileURLWithPath: "/tmp")
    private var sut: CommandRunnerService!
    private var launcher: MockCommandLauncherRepository!

    override func setUp() {
        super.setUp()
        launcher = MockCommandLauncherRepository()
        sut = CommandRunnerService(launcher: launcher)
    }

    override func tearDown() {
        sut = nil
        launcher = nil
        super.tearDown()
    }

    private func backgroundEntry(line: String = "/bin/ls -la") -> CommandEntry {
        CommandEntry(line: line, workingDirectory: nil, sink: .background)
    }

    private func terminalEntry() -> CommandEntry {
        CommandEntry(line: "/usr/bin/top", workingDirectory: nil, sink: .terminal)
    }

    // MARK: - .background

    // Background commands stream via `stream(_:)` (RunStreamingEntryUseCase); the
    // open path must refuse them rather than run them non-streamed.
    func test_perform_background_throwsInvalidItem() async throws {
        do {
            try await sut.perform(backgroundEntry(), preference: .default, currentDirectory: Self.currentDir)
            XCTFail("Expected perform to reject a background command")
        } catch let error as OperationError {
            guard case .invalidItem = error else {
                return XCTFail("Expected invalidItem, got \(error)")
            }
        }
    }

    func test_perform_background_doesNotRunInTerminal() async throws {
        _ = try? await sut.perform(backgroundEntry(), preference: .default, currentDirectory: Self.currentDir)
        XCTAssertEqual(launcher.runCommandInTerminalCallCount, 0)
    }

    // MARK: - .terminal

    func test_perform_terminal_callsRunInTerminalOnce() async throws {
        try await sut.perform(terminalEntry(), preference: .default, currentDirectory: Self.currentDir)
        XCTAssertEqual(launcher.runCommandInTerminalCallCount, 1)
    }

    func test_perform_terminal_passesGivenAppBundleID() async throws {
        let preference = TerminalPreference(selection: .known(.iterm), launchMode: .newWindow)
        try await sut.perform(terminalEntry(), preference: preference, currentDirectory: Self.currentDir)
        XCTAssertEqual(launcher.runCommandInTerminalBundleID, TerminalApp.iterm.bundleIdentifier)
    }

    func test_perform_terminal_passesGivenLaunchMode() async throws {
        let preference = TerminalPreference(selection: .known(.iterm), launchMode: .reuse)
        try await sut.perform(terminalEntry(), preference: preference, currentDirectory: Self.currentDir)
        XCTAssertEqual(launcher.runCommandInTerminalLaunchMode, .reuse)
    }

    func test_perform_terminal_forwardsCurrentDirectory() async throws {
        let dir = URL(fileURLWithPath: "/work/dir")
        try await sut.perform(terminalEntry(), preference: .default, currentDirectory: dir)
        XCTAssertEqual(launcher.runCommandInTerminalCurrentDirectory, dir)
    }

    func test_stream_background_forwardsCurrentDirectory() {
        let dir = URL(fileURLWithPath: "/work/dir")
        _ = sut.stream(backgroundEntry(), currentDirectory: dir)
        XCTAssertEqual(launcher.streamCommandInBackgroundCurrentDirectory, dir)
    }

    func test_stream_background_convertsWorkingDirectoryStringToURL() {
        let entry = CommandEntry(line: "ls", workingDirectory: "/some/dir", sink: .background)
        _ = sut.stream(entry, currentDirectory: Self.currentDir)
        XCTAssertEqual(launcher.streamCommandInBackgroundWorkingDirectory, URL(fileURLWithPath: "/some/dir"))
    }

    func test_perform_terminal_otherApp_throwsWithoutLaunching() async throws {
        let preference = TerminalPreference(
            selection: .other(bundleIdentifier: "com.example.warp", name: "Warp"),
            launchMode: .newWindow
        )
        do {
            _ = try await sut.perform(terminalEntry(), preference: preference, currentDirectory: Self.currentDir)
            XCTFail("Expected a terminalLaunchFailed error for a non-scriptable app")
        } catch let error as OperationError {
            guard case .terminalLaunchFailed = error else {
                return XCTFail("Expected terminalLaunchFailed, got \(error)")
            }
            XCTAssertEqual(launcher.runCommandInTerminalCallCount, 0)
        }
    }
}
