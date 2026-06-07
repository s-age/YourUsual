import XCTest
@testable import YourUsual

/// Locks `SliderPayload.toCommandDomain(value:currentDirectory:)`: the `<VALUE>` token is
/// replaced with the formatted value, the command always runs in the background, and the
/// passed current directory becomes its working directory (product decision: sliders run in
/// the global current directory).
final class SliderPayloadMappingTests: XCTestCase {
    private func payload(commandLine: String, step: Double = 1) -> SliderPayload {
        SliderPayload(commandLine: commandLine, minValue: 0, maxValue: 100, step: step, currentValue: 0)
    }

    func testToCommandDomain_substitutesValue() {
        let command = payload(commandLine: "set volume output volume <VALUE>")
            .toCommandDomain(value: 60, currentDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(command.line, "set volume output volume 60")
    }

    func testToCommandDomain_formatsValuePerStep() {
        let command = payload(commandLine: "brightness <VALUE>", step: 0.25)
            .toCommandDomain(value: 0.25, currentDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(command.line, "brightness 0.25")
    }

    func testToCommandDomain_runsInBackground() {
        let command = payload(commandLine: "echo <VALUE>")
            .toCommandDomain(value: 1, currentDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(command.sink, .background)
    }

    func testToCommandDomain_usesCurrentDirectoryAsWorkingDirectory() {
        let command = payload(commandLine: "echo <VALUE>")
            .toCommandDomain(value: 1, currentDirectory: URL(fileURLWithPath: "/work/dir"))
        XCTAssertEqual(command.workingDirectory, "/work/dir")
    }
}
