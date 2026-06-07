import Foundation

/// The mutable attributes of a pad cell, bundled so factories/transforms stay within
/// the parameter budget. Carries placement (origin + span) and appearance; the cell's
/// `id` and `layoutID` are assigned by `PadServiceProtocol.makePadCell`.
struct PadCellDraft: Equatable, Sendable {
    var column: Int
    var row: Int
    var columnSpan: Int
    var rowSpan: Int
    var entryID: UUID?
    var backgroundColor: String?
    var customIconName: String?
    var customIconImageName: String?  // normalized-PNG filename (under PadIcons/); nil = no image
    var customLabel: String?
    // How a slider cell renders (horizontal/vertical). Chosen on the Pad, not the entry, so the
    // same slider command can be placed either way. Ignored for button cells. Default horizontal.
    var sliderOrientation: SliderOrientation = .horizontal
}

struct PadCell: Identifiable, Equatable, Sendable {
    let id: UUID
    let layoutID: UUID
    var column: Int        // 0-based origin
    var row: Int           // 0-based origin
    var columnSpan: Int    // ≥1
    var rowSpan: Int       // ≥1
    var entryID: UUID?
    var backgroundColor: String?  // hex e.g. "#1A73E8"; nil = system default
    var customIconName: String?   // SF Symbol name; nil = entry's icon
    var customIconImageName: String?  // normalized-PNG filename; nil = no image (falls back to SF Symbol)
    var customLabel: String?      // nil = entry's name
    var sliderOrientation: SliderOrientation = .horizontal  // slider cells only; ignored for buttons

    /// Returns true when this cell occupies column `c`, row `r` (including spans).
    func covers(column c: Int, row r: Int) -> Bool {
        c >= column && c < column + columnSpan &&
        r >= row    && r < row    + rowSpan
    }

    /// Returns true when the cell fits within a grid of `columns` × `rows`.
    func fits(inColumns columns: Int, rows: Int) -> Bool {
        column >= 0 && row >= 0 &&
        column + columnSpan <= columns &&
        row    + rowSpan    <= rows
    }

    /// Returns true when this cell's rectangle intersects `other`'s rectangle
    /// (any shared grid square, accounting for both spans). Used to reject
    /// overlapping placements when a cell is added or its span is grown.
    func overlaps(_ other: PadCell) -> Bool {
        column < other.column + other.columnSpan &&
        other.column < column + columnSpan &&
        row < other.row + other.rowSpan &&
        other.row < row + rowSpan
    }
}

/// A square crop region in the source image's pixel coordinates: a `side`×`side` square.
/// Pixel integers (not normalized 0..1) remove fractional-aspect ambiguity when the value
/// crosses layers — Presentation computes it from the probed pixel dimensions.
struct IconCrop: Equatable, Sendable {
    let originX: Int   // top-left X (pixels)
    let originY: Int   // top-left Y (pixels)
    let side: Int      // edge length (pixels); square, so width == height
}

/// An image's pixel dimensions (the result of a lightweight probe).
struct PixelSize: Equatable, Sendable {
    let width: Int
    let height: Int
}
