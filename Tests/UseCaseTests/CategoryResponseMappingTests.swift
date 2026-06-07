import XCTest
@testable import YourUsual

/// Locks the `EntryCategory` → `CategoryResponse` mapping for the menu-bar visibility
/// flag, so Presentation can filter hidden categories and prefill the toggle.
final class CategoryResponseMappingTests: XCTestCase {
    private func category(isHiddenFromMenuBar: Bool) -> EntryCategory {
        EntryCategory(name: "Work", sortIndex: 2, isHiddenFromMenuBar: isHiddenFromMenuBar)
    }

    func testFromEntity_hidden_propagatesFlag() {
        XCTAssertTrue(CategoryResponse(from: category(isHiddenFromMenuBar: true)).isHiddenFromMenuBar)
    }

    func testFromEntity_visible_flagIsFalse() {
        XCTAssertFalse(CategoryResponse(from: category(isHiddenFromMenuBar: false)).isHiddenFromMenuBar)
    }
}
