import Foundation

/// Default cell background colour (as a `#RRGGBB` hex string).
///
/// The cell editor used to render a bespoke inline swatch grid here because the pad was
/// hosted in a non-activating floating `NSPanel`, where SwiftUI's `ColorPicker` is
/// unusable — its `NSColorPanel` can neither become key nor rise above the floating
/// panel. Cell editing has since moved into the Settings `Window` (a normal key window),
/// so `PadCellEditSheet` now uses a native `ColorPicker` and only needs a default seed.
enum PadColorPalette {
    /// Default selection when the user enables a custom background — a mid blue.
    static let defaultSwatch = "#0000FF"
}
