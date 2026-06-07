import XCTest
@testable import YourUsual

final class SliderEntryTests: XCTestCase {
    private func entry(min: Double = 0, max: Double = 100, current: Double = 50) -> SliderEntry {
        SliderEntry(commandLine: "echo <VALUE>", minValue: min, maxValue: max, step: 1, currentValue: current)
    }

    // MARK: - updating(currentValue:)

    func test_updating_withinBounds_setsValue() {
        let result = entry().updating(currentValue: 75)
        XCTAssertEqual(result.currentValue, 75)
    }

    func test_updating_aboveMax_clampsToMax() {
        let result = entry(max: 100).updating(currentValue: 250)
        XCTAssertEqual(result.currentValue, 100)
    }

    func test_updating_belowMin_clampsToMin() {
        let result = entry(min: 10).updating(currentValue: -5)
        XCTAssertEqual(result.currentValue, 10)
    }

    func test_updating_leavesOtherFieldsUnchanged() {
        let original = entry(min: 5, max: 90, current: 20)
        let result = original.updating(currentValue: 40)
        XCTAssertEqual(
            [result.commandLine, "\(result.minValue)", "\(result.maxValue)", "\(result.step)"],
            ["echo <VALUE>", "5.0", "90.0", "1.0"]
        )
    }
}
