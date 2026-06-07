import SwiftUI

extension Color {
    /// Initialises a `Color` from a CSS-style hex string (`"#RRGGBB"` or `"#RRGGBBAA"`).
    init?(hex: String) {
        guard let (r, g, b, a) = Color.rgba(hex: hex) else { return nil }
        self.init(red: r, green: g, blue: b, opacity: a)
    }

    /// Parses a CSS-style hex (`"#RRGGBB"` / `"#RRGGBBAA"`) into 0...1 RGBA components.
    private static func rgba(hex: String) -> (red: Double, green: Double, blue: Double, opacity: Double)? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned = String(cleaned.dropFirst()) }
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }
        guard let value = UInt64(cleaned, radix: 16) else { return nil }
        if cleaned.count == 8 {
            return (Double((value >> 24) & 0xFF) / 255, Double((value >> 16) & 0xFF) / 255,
                    Double((value >>  8) & 0xFF) / 255, Double( value        & 0xFF) / 255)
        }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255,
                Double( value        & 0xFF) / 255, 1.0)
    }

    /// A dark-or-light foreground that contrasts a hex background, chosen by WCAG relative
    /// luminance (the crossover sits at ≈ 0.179). Returns a softened near-black (`#333`) /
    /// near-white (`#ddd`) rather than pure `#000`/`#fff` — the extremes read as harsh against
    /// the saturated cell colours, so the tone is pulled in slightly while keeping ample
    /// contrast. Returns `nil` when the hex can't be parsed, so the caller falls back to `.primary`.
    static func readableForeground(onHex hex: String) -> Color? {
        guard let (r, g, b, _) = rgba(hex: hex) else { return nil }
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        return luminance > 0.179 ? Color(white: 0.2) : Color(white: 0.867)   // #333 / #ddd
    }

    /// Renders this colour as a `"#RRGGBB"` hex string (opacity dropped) by resolving it
    /// against the supplied environment. Used to store a `ColorPicker` selection in the
    /// hex-stored `PadCell.backgroundColor`. AppKit (`NSColor`) is off-limits in
    /// Presentation, so resolution goes through SwiftUI's `Color.Resolved`.
    func hexRGB(in environment: EnvironmentValues) -> String {
        let resolved = resolve(in: environment)
        func channel(_ v: Float) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X",
                      channel(resolved.red), channel(resolved.green), channel(resolved.blue))
    }
}
