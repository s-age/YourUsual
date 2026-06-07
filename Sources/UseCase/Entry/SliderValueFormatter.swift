import Foundation

/// Renders a slider value to the string injected for `<VALUE>`. Integer when `step` is a
/// whole number (e.g. volume `0...100` → "60"); otherwise uses the number of decimal places
/// the **step** declares, counted from its decimal text — NOT log10 (which breaks on steps
/// that aren't powers of ten: log10(0.25) ≈ -0.6 → would wrongly yield 1 decimal → "0.2").
enum SliderValueFormatter {
    static func format(_ value: Double, step: Double) -> String {
        let decimals = decimalPlaces(of: step)
        if decimals == 0 { return String(Int(value.rounded())) }
        return String(format: "%.\(decimals)f", value)
    }

    /// Decimal places implied by `step`, counted from its shortest decimal text.
    /// 1 → 0, 0.1 → 1, 0.25 → 2, 0.05 → 2. Uses the value's own description (Swift prints
    /// the shortest round-tripping form) and counts digits after the dot.
    private static func decimalPlaces(of step: Double) -> Int {
        let text = String(step)                 // e.g. "0.25", "1.0", "0.05", "1e-05"
        // Very small steps print in scientific notation ("1e-05"), which has no dot — a naive
        // dot-scan would wrongly yield 0 decimals and integer-format the value, losing the
        // step's precision. Recover the place count from the mantissa's fraction length minus
        // the (negative) exponent: "1e-05" → 5, "1.5e-3" → 4.
        if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            let mantissa = text[..<e]
            let exponent = Int(text[text.index(after: e)...]) ?? 0
            let mantissaFraction = mantissa.firstIndex(of: ".").map {
                mantissa.distance(from: mantissa.index(after: $0), to: mantissa.endIndex)
            } ?? 0
            return max(0, mantissaFraction - exponent)
        }
        guard let dot = text.firstIndex(of: ".") else { return 0 }
        let fraction = text[text.index(after: dot)...]
        if fraction == "0" { return 0 }         // "1.0" → integer step
        return fraction.count
    }
}
