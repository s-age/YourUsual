import XCTest
@testable import YourUsual

final class RegisterCategoryRequestTests: XCTestCase {

    func test_validate_emptyName_throwsEmptyField() {
        XCTAssertThrowsError(try RegisterCategoryRequest(name: "").validate()) { error in
            guard case ValidationError.emptyField = error else {
                return XCTFail("Expected ValidationError.emptyField, got \(error)")
            }
        }
    }

    func test_validate_whitespaceOnlyName_throwsEmptyField() {
        XCTAssertThrowsError(try RegisterCategoryRequest(name: "   ").validate()) { error in
            guard case ValidationError.emptyField = error else {
                return XCTFail("Expected ValidationError.emptyField, got \(error)")
            }
        }
    }

    func test_validate_nonEmptyName_doesNotThrow() {
        XCTAssertNoThrow(try RegisterCategoryRequest(name: "Work").validate())
    }

    func test_validate_nameOverLimit_throwsOutOfRange() {
        XCTAssertThrowsError(
            try RegisterCategoryRequest(name: String(repeating: "a", count: 201)).validate()
        ) { error in
            guard case ValidationError.outOfRange(let field, _) = error else {
                return XCTFail("Expected ValidationError.outOfRange, got \(error)")
            }
            XCTAssertEqual(field, "category name")
        }
    }

    func test_validate_nameAtLimit_doesNotThrow() {
        XCTAssertNoThrow(try RegisterCategoryRequest(name: String(repeating: "a", count: 200)).validate())
    }
}
