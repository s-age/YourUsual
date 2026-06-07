import XCTest
@testable import YourUsual

final class ValidationErrorTests: XCTestCase {

    // MARK: - Equatable: equal cases

    func testEmptyField_sameName_areEqual() {
        XCTAssertEqual(
            ValidationError.emptyField(name: "name"),
            ValidationError.emptyField(name: "name")
        )
    }

    // MARK: - Equatable: differing associated values

    func testEmptyField_differentName_areNotEqual() {
        XCTAssertNotEqual(
            ValidationError.emptyField(name: "name"),
            ValidationError.emptyField(name: "path")
        )
    }

    // MARK: - errorDescription copy

    func testEmptyField_errorDescription_matchesSpec() {
        XCTAssertEqual(
            ValidationError.emptyField(name: "category name").errorDescription,
            "category name is empty"
        )
    }
}
