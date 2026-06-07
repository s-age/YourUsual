import XCTest
@testable import YourUsual

/// Locks the `<VALUE>` rendering rule. The decimal count is derived from the **step's**
/// shortest decimal text, not log10 — so non-power-of-ten steps (0.25, 0.05) keep their
/// digits instead of collapsing to one place.
final class SliderValueFormatterTests: XCTestCase {
    func testFormat_integerStep_rendersInteger() {
        XCTAssertEqual(SliderValueFormatter.format(60, step: 1), "60")
    }

    func testFormat_integerStep_roundsValue() {
        XCTAssertEqual(SliderValueFormatter.format(59.6, step: 1), "60")
    }

    func testFormat_wholeDoubleStep_treatedAsInteger() {
        XCTAssertEqual(SliderValueFormatter.format(60, step: 1.0), "60")
    }

    func testFormat_tenthStep_rendersOneDecimal() {
        XCTAssertEqual(SliderValueFormatter.format(0.5, step: 0.1), "0.5")
    }

    func testFormat_quarterStep_rendersTwoDecimals() {
        // Regression: log10(0.25) would wrongly yield one decimal ("0.2").
        XCTAssertEqual(SliderValueFormatter.format(0.25, step: 0.25), "0.25")
    }

    func testFormat_twentiethStep_rendersTwoDecimals() {
        XCTAssertEqual(SliderValueFormatter.format(0.15, step: 0.05), "0.15")
    }

    func testFormat_tinyStepInScientificNotation_keepsDecimals() {
        // `String(1e-05)` == "1e-05" (no dot) — a naive dot-scan would integer-format the
        // value. The exponent must drive the decimal count instead (5 places here).
        XCTAssertEqual(SliderValueFormatter.format(0.00003, step: 0.00001), "0.00003")
    }
}
