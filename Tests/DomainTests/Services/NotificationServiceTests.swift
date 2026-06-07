import XCTest
@testable import YourUsual

final class NotificationServiceTests: XCTestCase {
    private var sut: NotificationService!
    private var notifier: MockNotifierRepository!

    override func setUp() {
        super.setUp()
        notifier = MockNotifierRepository()
        sut = NotificationService(notifier: notifier)
    }

    override func tearDown() {
        sut = nil
        notifier = nil
        super.tearDown()
    }

    private func result(exitCode: Int32 = 0, stdout: String = "", stderr: String = "") -> CommandResult {
        CommandResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    // MARK: - result present

    func test_notifyIfNeeded_withResult_notifiesOnce() async {
        await sut.notifyIfNeeded(name: "List", result: result())
        XCTAssertEqual(notifier.notifyCallCount, 1)
    }

    func test_notifyIfNeeded_usesNameAsTitle() async {
        await sut.notifyIfNeeded(name: "List", result: result())
        XCTAssertEqual(notifier.notifyTitle, "List")
    }

    func test_notifyIfNeeded_successExitCode_notifiesSuccessBody() async {
        await sut.notifyIfNeeded(name: "List", result: result(exitCode: 0, stdout: "ok"))
        XCTAssertTrue(notifier.notifyBody?.contains("Completed") ?? false)
    }

    func test_notifyIfNeeded_failureExitCode_notifiesFailureBody() async {
        await sut.notifyIfNeeded(name: "List", result: result(exitCode: 1, stderr: "boom"))
        XCTAssertTrue(notifier.notifyBody?.contains("Failed") ?? false)
    }

    // MARK: - nil result

    func test_notifyIfNeeded_nilResult_doesNotNotify() async {
        await sut.notifyIfNeeded(name: "Top", result: nil)
        XCTAssertEqual(notifier.notifyCallCount, 0)
    }

    // MARK: - completion

    func test_notifyCompletion_usesNameAsTitle() async {
        await sut.notifyCompletion(name: "Script")
        XCTAssertEqual(notifier.notifyTitle, "Script")
    }

    func test_notifyCompletion_notifiesCompletedBody() async {
        await sut.notifyCompletion(name: "Script")
        XCTAssertEqual(notifier.notifyBody, "Completed")
    }
}
