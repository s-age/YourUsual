import XCTest
@testable import YourUsual

/// Locks the `SavedEntry` → `SavedEntryResponse` mapping for the recovery marker, so a
/// recovered placeholder stays distinguishable all the way to Presentation (badge +
/// overwrite confirmation).
final class SavedEntryResponseMappingTests: XCTestCase {
    private func entry(isRecovered: Bool, isHiddenFromMenuBar: Bool = false) -> SavedEntry {
        SavedEntry(
            name: "x",
            kind: .browse(BrowseEntry(url: URL(fileURLWithPath: "/tmp/x"), app: .default)),
            sortIndex: 0,
            isRecovered: isRecovered,
            isHiddenFromMenuBar: isHiddenFromMenuBar
        )
    }

    func testFromEntity_recovered_propagatesFlag() {
        XCTAssertTrue(SavedEntryResponse(from: entry(isRecovered: true)).isRecovered)
    }

    func testFromEntity_normal_flagIsFalse() {
        XCTAssertFalse(SavedEntryResponse(from: entry(isRecovered: false)).isRecovered)
    }

    func testFromEntity_hiddenFromMenuBar_propagatesFlag() {
        let response = SavedEntryResponse(from: entry(isRecovered: false, isHiddenFromMenuBar: true))
        XCTAssertTrue(response.isHiddenFromMenuBar)
    }

    func testFromEntity_visible_flagIsFalse() {
        let response = SavedEntryResponse(from: entry(isRecovered: false, isHiddenFromMenuBar: false))
        XCTAssertFalse(response.isHiddenFromMenuBar)
    }
}
