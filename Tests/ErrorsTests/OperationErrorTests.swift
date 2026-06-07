import XCTest
@testable import YourUsual

final class OperationErrorTests: XCTestCase {

    // MARK: - Equatable: equal cases

    func testInvalidItem_sameReason_areEqual() {
        XCTAssertEqual(
            OperationError.invalidItem(reason: "empty name"),
            OperationError.invalidItem(reason: "empty name")
        )
    }

    func testItemNotFound_sameID_areEqual() {
        let id = UUID()
        XCTAssertEqual(
            OperationError.itemNotFound(id: id),
            OperationError.itemNotFound(id: id)
        )
    }

    func testTargetNotFound_samePath_areEqual() {
        XCTAssertEqual(
            OperationError.targetNotFound(path: "/tmp/x"),
            OperationError.targetNotFound(path: "/tmp/x")
        )
    }

    func testAppNotFound_sameBundleIdentifier_areEqual() {
        XCTAssertEqual(
            OperationError.appNotFound(bundleIdentifier: "com.apple.Terminal"),
            OperationError.appNotFound(bundleIdentifier: "com.apple.Terminal")
        )
    }

    func testCommandFailed_sameExitCodeAndStderr_areEqual() {
        XCTAssertEqual(
            OperationError.commandFailed(exitCode: 1, stderr: "boom"),
            OperationError.commandFailed(exitCode: 1, stderr: "boom")
        )
    }

    func testTerminalLaunchFailed_sameReason_areEqual() {
        XCTAssertEqual(
            OperationError.terminalLaunchFailed(reason: "no iTerm"),
            OperationError.terminalLaunchFailed(reason: "no iTerm")
        )
    }

    func testPersistenceFailed_sameReason_areEqual() {
        XCTAssertEqual(
            OperationError.persistenceFailed(reason: "disk full"),
            OperationError.persistenceFailed(reason: "disk full")
        )
    }

    // MARK: - Equatable: differing associated values

    func testInvalidItem_differentReason_areNotEqual() {
        XCTAssertNotEqual(
            OperationError.invalidItem(reason: "empty name"),
            OperationError.invalidItem(reason: "empty path")
        )
    }

    func testItemNotFound_differentID_areNotEqual() {
        XCTAssertNotEqual(
            OperationError.itemNotFound(id: UUID()),
            OperationError.itemNotFound(id: UUID())
        )
    }

    func testTargetNotFound_differentPath_areNotEqual() {
        XCTAssertNotEqual(
            OperationError.targetNotFound(path: "/tmp/x"),
            OperationError.targetNotFound(path: "/tmp/y")
        )
    }

    func testAppNotFound_differentBundleIdentifier_areNotEqual() {
        XCTAssertNotEqual(
            OperationError.appNotFound(bundleIdentifier: "com.apple.Terminal"),
            OperationError.appNotFound(bundleIdentifier: "com.googlecode.iterm2")
        )
    }

    func testCommandFailed_differentExitCode_areNotEqual() {
        XCTAssertNotEqual(
            OperationError.commandFailed(exitCode: 1, stderr: "boom"),
            OperationError.commandFailed(exitCode: 2, stderr: "boom")
        )
    }

    func testCommandFailed_differentStderr_areNotEqual() {
        XCTAssertNotEqual(
            OperationError.commandFailed(exitCode: 1, stderr: "boom"),
            OperationError.commandFailed(exitCode: 1, stderr: "bang")
        )
    }

    func testTerminalLaunchFailed_differentReason_areNotEqual() {
        XCTAssertNotEqual(
            OperationError.terminalLaunchFailed(reason: "no iTerm"),
            OperationError.terminalLaunchFailed(reason: "no Terminal")
        )
    }

    func testPersistenceFailed_differentReason_areNotEqual() {
        XCTAssertNotEqual(
            OperationError.persistenceFailed(reason: "disk full"),
            OperationError.persistenceFailed(reason: "permission denied")
        )
    }

    // MARK: - Equatable: differing cases

    func testInvalidItemVsTargetNotFound_differentCases_areNotEqual() {
        XCTAssertNotEqual(
            OperationError.invalidItem(reason: "x"),
            OperationError.targetNotFound(path: "x")
        )
    }

    // MARK: - errorDescription copy

    func testInvalidItem_errorDescription_matchesSpec() {
        XCTAssertEqual(
            OperationError.invalidItem(reason: "empty name").errorDescription,
            "Invalid item: empty name"
        )
    }

    func testItemNotFound_errorDescription_matchesSpec() {
        let id = UUID()
        XCTAssertEqual(
            OperationError.itemNotFound(id: id).errorDescription,
            "Item not found: \(id)"
        )
    }

    func testTargetNotFound_errorDescription_matchesSpec() {
        XCTAssertEqual(
            OperationError.targetNotFound(path: "/Users/me/file.txt").errorDescription,
            "Path not found: /Users/me/file.txt"
        )
    }

    func testAppNotFound_errorDescription_matchesSpec() {
        XCTAssertEqual(
            OperationError.appNotFound(bundleIdentifier: "com.apple.Terminal").errorDescription,
            "App not found: com.apple.Terminal"
        )
    }

    func testCommandFailed_errorDescription_matchesSpec() {
        XCTAssertEqual(
            OperationError.commandFailed(exitCode: 127, stderr: "command not found").errorDescription,
            "Command failed (exit 127)"
        )
    }

    func testTerminalLaunchFailed_errorDescription_matchesSpec() {
        XCTAssertEqual(
            OperationError.terminalLaunchFailed(reason: "iTerm2 not installed").errorDescription,
            "Terminal launch failed: iTerm2 not installed"
        )
    }

    func testPersistenceFailed_errorDescription_matchesSpec() {
        XCTAssertEqual(
            OperationError.persistenceFailed(reason: "disk full").errorDescription,
            "Could not save registry: disk full"
        )
    }
}
