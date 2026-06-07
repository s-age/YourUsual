import XCTest
@testable import YourUsual

/// `ReuseWindowStore` validates that a window id is a plain ASCII integer before it is
/// stored or returned, since the value is spliced into AppleScript source. These tests
/// pin that guard — especially that non-ASCII Unicode digits (which the old
/// `allSatisfy(\.isNumber)` check accepted) are rejected.
///
/// The store reads `UserDefaults.standard` directly, so each test uses a unique,
/// ephemeral key and removes it afterward to stay isolated.
final class ReuseWindowStoreTests: XCTestCase {
    private var sut: ReuseWindowStore!
    private var terminal: String!

    override func setUp() {
        super.setUp()
        sut = ReuseWindowStore()
        terminal = "test.\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "terminalReuseWindowID.\(terminal!)")
        sut = nil
        terminal = nil
        super.tearDown()
    }

    func testSetThenGet_plainInteger_roundTrips() {
        sut.setReuseWindowID("12345", forTerminal: terminal)
        XCTAssertEqual(sut.reuseWindowID(forTerminal: terminal), "12345")
    }

    func testSet_nonASCIIDigits_isRejected() {
        sut.setReuseWindowID("１２３", forTerminal: terminal)   // fullwidth digits (Nd, non-ASCII)
        XCTAssertNil(sut.reuseWindowID(forTerminal: terminal))
    }

    func testSet_nonNumeric_isRejected() {
        sut.setReuseWindowID("12 or delete window 1", forTerminal: terminal)
        XCTAssertNil(sut.reuseWindowID(forTerminal: terminal))
    }

    func testGet_storedNonASCIIDigits_isRejectedOnRead() {
        // A malformed value an older, looser build could have persisted: Arabic-Indic
        // digits pass `allSatisfy(\.isNumber)` but are not an ASCII integer.
        UserDefaults.standard.set("١٢٣", forKey: "terminalReuseWindowID.\(terminal!)")
        XCTAssertNil(sut.reuseWindowID(forTerminal: terminal))
    }
}
