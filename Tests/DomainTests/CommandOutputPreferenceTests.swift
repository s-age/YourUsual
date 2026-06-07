import XCTest
@testable import YourUsual

/// Verifies the valid-range clamp that keeps an out-of-range stored/entered value
/// from ever taking effect.
final class CommandOutputPreferenceTests: XCTestCase {

    func testInit_valueInRange_isKept() {
        XCTAssertEqual(CommandOutputPreference(bufferLines: 2000).bufferLines, 2000)
    }

    func testInit_belowMinimum_clampsToMinimum() {
        XCTAssertEqual(
            CommandOutputPreference(bufferLines: 1).bufferLines,
            CommandOutputPreference.minBufferLines
        )
    }

    func testInit_aboveMaximum_clampsToMaximum() {
        XCTAssertEqual(
            CommandOutputPreference(bufferLines: 10_000_000).bufferLines,
            CommandOutputPreference.maxBufferLines
        )
    }

    func testDefault_is1000Lines() {
        XCTAssertEqual(CommandOutputPreference.default.bufferLines, 1000)
    }
}
