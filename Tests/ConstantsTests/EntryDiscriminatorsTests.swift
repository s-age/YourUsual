import XCTest
@testable import YourUsual

/// The discriminator `rawValue`s are a **persisted storage contract**: they are written
/// into the registry store, so renaming a case (changing its rawValue) would silently
/// fail to match existing on-disk data. These tests pin the exact strings so such a
/// change can't slip through unnoticed.
final class EntryDiscriminatorsTests: XCTestCase {

    func testTargetKind_rawValues_matchPersistedContract() {
        XCTAssertEqual(TargetKind.path.rawValue, "path")
        XCTAssertEqual(TargetKind.command.rawValue, "command")
        XCTAssertEqual(TargetKind.applescript.rawValue, "applescript")
    }

    func testHandlerKind_rawValues_matchPersistedContract() {
        XCTAssertEqual(HandlerKind.defaultApp.rawValue, "defaultApp")
        XCTAssertEqual(HandlerKind.app.rawValue, "app")
        XCTAssertEqual(HandlerKind.background.rawValue, "background")
        XCTAssertEqual(HandlerKind.terminal.rawValue, "terminal")
        XCTAssertEqual(HandlerKind.applescript.rawValue, "applescript")
    }
}
