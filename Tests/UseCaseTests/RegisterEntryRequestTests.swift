import XCTest
@testable import YourUsual

final class RegisterEntryRequestTests: XCTestCase {

    // MARK: - Helpers

    private func assertEmptyField(
        _ request: RegisterEntryRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try request.validate(), file: file, line: line) { error in
            guard case ValidationError.emptyField = error else {
                return XCTFail("Expected ValidationError.emptyField, got \(error)", file: file, line: line)
            }
        }
    }

    private func assertOutOfRange(
        _ request: RegisterEntryRequest,
        field expectedField: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try request.validate(), file: file, line: line) { error in
            guard case ValidationError.outOfRange(let field, _) = error else {
                return XCTFail("Expected ValidationError.outOfRange, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(field, expectedField, file: file, line: line)
        }
    }

    // MARK: - Empty fields

    func test_validate_emptyName_throwsEmptyField() {
        let request = RegisterEntryRequest(
            name: "",
            kind: .browse(BrowsePayload(path: "/tmp/notes.txt", app: .default))
        )
        assertEmptyField(request)
    }

    func test_validate_emptyPath_throwsEmptyField() {
        let request = RegisterEntryRequest(
            name: "Notes",
            kind: .browse(BrowsePayload(path: "", app: .default))
        )
        assertEmptyField(request)
    }

    func test_validate_whitespaceOnlyPath_throwsEmptyField() {
        let request = RegisterEntryRequest(
            name: "Notes",
            kind: .browse(BrowsePayload(path: "   ", app: .default))
        )
        assertEmptyField(request)
    }

    func test_validate_emptyCommandLine_throwsEmptyField() {
        let request = RegisterEntryRequest(
            name: "List",
            kind: .command(CommandPayload(commandLine: "", workingDirectory: nil, sink: .background))
        )
        assertEmptyField(request)
    }

    // MARK: - Max length (field ceilings)

    func test_validate_nameOverLimit_throwsOutOfRange() {
        let request = RegisterEntryRequest(
            name: String(repeating: "a", count: 201),
            kind: .browse(BrowsePayload(path: "/tmp/notes.txt", app: .default))
        )
        assertOutOfRange(request, field: "name")
    }

    func test_validate_nameAtLimit_doesNotThrow() {
        let request = RegisterEntryRequest(
            name: String(repeating: "a", count: 200),
            kind: .browse(BrowsePayload(path: "/tmp/notes.txt", app: .default))
        )
        XCTAssertNoThrow(try request.validate())
    }

    func test_validate_browsePathOverLimit_throwsOutOfRange() {
        let request = RegisterEntryRequest(
            name: "Notes",
            kind: .browse(BrowsePayload(path: "/" + String(repeating: "a", count: 1024), app: .default))
        )
        assertOutOfRange(request, field: "path")
    }

    func test_validate_commandLineOverLimit_throwsOutOfRange() {
        let request = RegisterEntryRequest(
            name: "List",
            kind: .command(CommandPayload(
                commandLine: String(repeating: "x", count: 1001), workingDirectory: nil, sink: .background))
        )
        assertOutOfRange(request, field: "command")
    }

    func test_validate_appleScriptSourceOverLimit_throwsOutOfRange() {
        let request = RegisterEntryRequest(
            name: "Script",
            kind: .appleScript(AppleScriptPayload(source: String(repeating: "s", count: 10001)))
        )
        assertOutOfRange(request, field: "AppleScript source")
    }

    func test_validate_sliderCommandLineOverLimit_throwsOutOfRange() {
        // The slider command must still contain <VALUE>; the length check fires on the trimmed
        // command before the token check, so the field reported is "Command".
        let longCommand = "set volume output volume <VALUE> " + String(repeating: "x", count: 1000)
        let request = RegisterEntryRequest(
            name: "Volume",
            kind: .slider(SliderPayload(
                commandLine: longCommand, minValue: 0, maxValue: 100, step: 1, currentValue: 0))
        )
        assertOutOfRange(request, field: "Command")
    }

    // MARK: - Valid kinds

    func test_validate_browseWithDefaultApp_doesNotThrow() {
        let request = RegisterEntryRequest(
            name: "Notes",
            kind: .browse(BrowsePayload(path: "/tmp/notes.txt", app: .default))
        )
        XCTAssertNoThrow(try request.validate())
    }

    func test_validate_browseWithApp_doesNotThrow() {
        let request = RegisterEntryRequest(
            name: "Notes",
            kind: .browse(BrowsePayload(path: "/tmp/notes.txt", app: .app(bundleIdentifier: "com.apple.TextEdit")))
        )
        XCTAssertNoThrow(try request.validate())
    }

    func test_validate_commandWithBackground_doesNotThrow() {
        let request = RegisterEntryRequest(
            name: "List",
            kind: .command(CommandPayload(commandLine: "/bin/ls -la", workingDirectory: nil, sink: .background))
        )
        XCTAssertNoThrow(try request.validate())
    }

    func test_validate_commandWithTerminal_doesNotThrow() {
        let request = RegisterEntryRequest(
            name: "Top",
            kind: .command(CommandPayload(commandLine: "/usr/bin/top", workingDirectory: nil, sink: .terminal))
        )
        XCTAssertNoThrow(try request.validate())
    }

    // MARK: - Slider

    private func sliderRequest(
        commandLine: String = "set volume output volume <VALUE>",
        minValue: Double = 0, maxValue: Double = 100, step: Double = 1
    ) -> RegisterEntryRequest {
        RegisterEntryRequest(
            name: "Volume",
            kind: .slider(SliderPayload(
                commandLine: commandLine, minValue: minValue, maxValue: maxValue,
                step: step, currentValue: minValue
            ))
        )
    }

    func test_validate_sliderWithValueToken_doesNotThrow() {
        XCTAssertNoThrow(try sliderRequest().validate())
    }

    func test_validate_sliderEmptyCommand_throwsEmptyField() {
        assertEmptyField(sliderRequest(commandLine: "   "))
    }

    func test_validate_sliderMissingValueToken_throwsInvalidFormat() {
        XCTAssertThrowsError(try sliderRequest(commandLine: "set volume output volume 50").validate()) { error in
            guard case ValidationError.invalidFormat(let field, _) = error else {
                return XCTFail("Expected ValidationError.invalidFormat, got \(error)")
            }
            XCTAssertEqual(field, "Command")
        }
    }

    func test_validate_sliderMinNotLessThanMax_throwsOutOfRange() {
        XCTAssertThrowsError(try sliderRequest(minValue: 100, maxValue: 100).validate()) { error in
            guard case ValidationError.outOfRange(let field, _) = error else {
                return XCTFail("Expected ValidationError.outOfRange, got \(error)")
            }
            XCTAssertEqual(field, "Range")
        }
    }

    func test_validate_sliderNonPositiveStep_throwsOutOfRange() {
        XCTAssertThrowsError(try sliderRequest(step: 0).validate()) { error in
            guard case ValidationError.outOfRange(let field, _) = error else {
                return XCTFail("Expected ValidationError.outOfRange, got \(error)")
            }
            XCTAssertEqual(field, "Step")
        }
    }
}
