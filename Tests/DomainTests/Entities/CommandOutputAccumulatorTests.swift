import XCTest
@testable import YourUsual

/// Verifies the output fold: stdout/stderr are accumulated into separate bounded
/// buffers, `.exit` carries no body, and `result(exitCode:)` assembles the record.
final class CommandOutputAccumulatorTests: XCTestCase {

    func testResult_capturesStdoutSeparately() {
        var sut = CommandOutputAccumulator(maxLines: 100)
        sut.ingest(.stdout("out\n"))
        sut.ingest(.stderr("err\n"))
        XCTAssertEqual(sut.result(exitCode: 0).stdout, "out")
    }

    func testResult_capturesStderrSeparately() {
        var sut = CommandOutputAccumulator(maxLines: 100)
        sut.ingest(.stdout("out\n"))
        sut.ingest(.stderr("err\n"))
        XCTAssertEqual(sut.result(exitCode: 0).stderr, "err")
    }

    func testResult_usesGivenExitCode() {
        var sut = CommandOutputAccumulator(maxLines: 100)
        XCTAssertEqual(sut.result(exitCode: 3).exitCode, 3)
    }

    func testIngest_exit_leavesStdoutEmpty() {
        var sut = CommandOutputAccumulator(maxLines: 100)
        sut.ingest(.exit(0))
        XCTAssertEqual(sut.result(exitCode: 0).stdout, "")
    }

    func testResult_appliesLineRetentionToStdout() {
        var sut = CommandOutputAccumulator(maxLines: 2)
        sut.ingest(.stdout("1\n2\n3\n4\n"))
        XCTAssertEqual(sut.result(exitCode: 0).stdout,
                       "… (earlier output dropped; keeping the last 2 lines)\n3\n4")
    }
}
