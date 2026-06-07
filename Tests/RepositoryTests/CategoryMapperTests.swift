import XCTest
@testable import YourUsual

/// Round-trip coverage for `CategoryMapper` — the single source of truth for
/// `EntryCategory` ⇄ `CategoryDTO`. Asserts every field (here: the menu-bar
/// visibility flag) survives entity → DTO → entity in both states.
final class CategoryMapperTests: XCTestCase {

    func test_roundTrip_isHiddenFromMenuBar_true_survives() {
        let category = EntryCategory(name: "Work", sortIndex: 3, isHiddenFromMenuBar: true)
        let restored = CategoryMapper.toEntity(CategoryMapper.toDTO(category))
        XCTAssertTrue(restored.isHiddenFromMenuBar)
    }

    func test_roundTrip_isHiddenFromMenuBar_false_survives() {
        let category = EntryCategory(name: "Work", sortIndex: 3, isHiddenFromMenuBar: false)
        let restored = CategoryMapper.toEntity(CategoryMapper.toDTO(category))
        XCTAssertFalse(restored.isHiddenFromMenuBar)
    }

    func test_roundTrip_preservesIdNameSortIndex() {
        let category = EntryCategory(name: "Work", sortIndex: 3, isHiddenFromMenuBar: true)
        let restored = CategoryMapper.toEntity(CategoryMapper.toDTO(category))
        XCTAssertEqual(restored, category)
    }
}
