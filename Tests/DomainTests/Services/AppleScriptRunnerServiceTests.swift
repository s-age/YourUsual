import XCTest
@testable import YourUsual

final class AppleScriptRunnerServiceTests: XCTestCase {
    private var sut: AppleScriptRunnerService!
    private var launcher: MockAppleScriptLauncherRepository!

    override func setUp() {
        super.setUp()
        launcher = MockAppleScriptLauncherRepository()
        sut = AppleScriptRunnerService(launcher: launcher)
    }

    override func tearDown() {
        sut = nil
        launcher = nil
        super.tearDown()
    }

    func test_run_callsRunAppleScriptOnce() async throws {
        _ = try await sut.run(AppleScriptEntry(source: "return 1 + 1"))
        XCTAssertEqual(launcher.runAppleScriptCallCount, 1)
    }

    func test_run_passesEntrySource() async throws {
        _ = try await sut.run(AppleScriptEntry(source: "display dialog \"hi\""))
        XCTAssertEqual(launcher.runAppleScriptSource, "display dialog \"hi\"")
    }

    func test_run_returnsLauncherResult() async throws {
        launcher.runAppleScriptResult = "42"
        let result = try await sut.run(AppleScriptEntry(source: "return 42"))
        XCTAssertEqual(result, "42")
    }

    func test_run_nilLauncherResult_returnsNil() async throws {
        launcher.runAppleScriptResult = nil
        let result = try await sut.run(AppleScriptEntry(source: "return"))
        XCTAssertNil(result)
    }
}
