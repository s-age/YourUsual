import XCTest
@testable import YourUsual

final class PadRequestsTests: XCTestCase {

    // MARK: - RegisterPadLayoutRequest: name length

    func test_layout_validate_nameOverLimit_throwsOutOfRange() {
        XCTAssertThrowsError(
            try RegisterPadLayoutRequest(name: String(repeating: "a", count: 201), columns: 4, rows: 3).validate()
        ) { error in
            guard case ValidationError.outOfRange(let field, _) = error else {
                return XCTFail("Expected ValidationError.outOfRange, got \(error)")
            }
            XCTAssertEqual(field, "Name")
        }
    }

    func test_layout_validate_nameAtLimit_doesNotThrow() {
        XCTAssertNoThrow(
            try RegisterPadLayoutRequest(name: String(repeating: "a", count: 200), columns: 4, rows: 3).validate())
    }

    // MARK: - SavePadCellRequest fixtures

    private func cellRequest(
        backgroundColor: String? = nil,
        customLabel: String? = nil
    ) -> SavePadCellRequest {
        SavePadCellRequest(
            layoutID: UUID(), column: 0, row: 0, columnSpan: 1, rowSpan: 1,
            entryID: nil,
            backgroundColor: backgroundColor, customIconName: nil, customLabel: customLabel,
            sliderOrientation: .horizontal,
            customIconImageName: nil, newIconSourcePath: nil, newIconCrop: nil,
            previousIconImageName: nil
        )
    }

    private func assertInvalidFormat(
        _ request: SavePadCellRequest,
        field expectedField: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try request.validate(), file: file, line: line) { error in
            guard case ValidationError.invalidFormat(let field, _) = error else {
                return XCTFail("Expected ValidationError.invalidFormat, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(field, expectedField, file: file, line: line)
        }
    }

    // MARK: - SavePadCellRequest: backgroundColor hex

    func test_cell_validate_namedColor_throwsInvalidFormat() {
        assertInvalidFormat(cellRequest(backgroundColor: "blue"), field: "backgroundColor")
    }

    func test_cell_validate_nonHexDigits_throwsInvalidFormat() {
        assertInvalidFormat(cellRequest(backgroundColor: "#GGGGGG"), field: "backgroundColor")
    }

    func test_cell_validate_tooFewHexDigits_throwsInvalidFormat() {
        assertInvalidFormat(cellRequest(backgroundColor: "#12345"), field: "backgroundColor")
    }

    func test_cell_validate_validHexColor_doesNotThrow() {
        XCTAssertNoThrow(try cellRequest(backgroundColor: "#1A73E8").validate())
    }

    /// The accepted set mirrors `Color(hex:)`, which also parses 8-digit `#RRGGBBAA`
    /// (alpha) — so an alpha-bearing value must pass validation, not be rejected on save.
    func test_cell_validate_validHexColorWithAlpha_doesNotThrow() {
        XCTAssertNoThrow(try cellRequest(backgroundColor: "#1A73E8FF").validate())
    }

    /// Only 6 or 8 digits are valid; a 7-digit string is neither RGB nor RGBA.
    func test_cell_validate_sevenHexDigits_throwsInvalidFormat() {
        assertInvalidFormat(cellRequest(backgroundColor: "#1234567"), field: "backgroundColor")
    }

    func test_cell_validate_nilBackgroundColor_doesNotThrow() {
        XCTAssertNoThrow(try cellRequest(backgroundColor: nil).validate())
    }

    func test_cell_validate_emptyBackgroundColor_doesNotThrow() {
        XCTAssertNoThrow(try cellRequest(backgroundColor: "").validate())
    }

    // MARK: - SavePadCellRequest: customLabel length

    func test_cell_validate_customLabelOverLimit_throwsOutOfRange() {
        XCTAssertThrowsError(
            try cellRequest(customLabel: String(repeating: "a", count: 101)).validate()
        ) { error in
            guard case ValidationError.outOfRange(let field, _) = error else {
                return XCTFail("Expected ValidationError.outOfRange, got \(error)")
            }
            XCTAssertEqual(field, "customLabel")
        }
    }

    func test_cell_validate_customLabelAtLimit_doesNotThrow() {
        XCTAssertNoThrow(try cellRequest(customLabel: String(repeating: "a", count: 100)).validate())
    }
}
