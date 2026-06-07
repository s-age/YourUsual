import XCTest
@testable import YourUsual

final class TerminalAppTests: XCTestCase {

    // MARK: - TerminalApp.bundleIdentifier

    func test_bundleIdentifier_terminal_isAppleTerminal() {
        XCTAssertEqual(TerminalApp.terminal.bundleIdentifier, "com.apple.Terminal")
    }

    func test_bundleIdentifier_iterm_isIterm2() {
        XCTAssertEqual(TerminalApp.iterm.bundleIdentifier, "com.googlecode.iterm2")
    }

    // MARK: - CommandResult.succeeded

    func test_succeeded_exitCodeZero_isTrue() {
        let result = CommandResult(exitCode: 0, stdout: "", stderr: "")
        XCTAssertTrue(result.succeeded)
    }

    func test_succeeded_nonZeroExitCode_isFalse() {
        let result = CommandResult(exitCode: 1, stdout: "", stderr: "")
        XCTAssertFalse(result.succeeded)
    }
}
