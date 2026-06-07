import Foundation

struct PadLayoutResponse: Equatable, Sendable {
    let id: UUID
    let name: String
    let columns: Int
    let rows: Int
    let sortIndex: Int
}

struct PadCellResponse: Identifiable, Equatable, Sendable {
    let id: UUID
    let layoutID: UUID
    let column: Int
    let row: Int
    let columnSpan: Int
    let rowSpan: Int
    let entryID: UUID?               // raw stored linkage (may be a dangling id if entry deleted)
    let entry: SavedEntryResponse?  // resolved snapshot — nil when entryID is nil or entry not found.
                                    // Carries name, kind (→ icon via kind.iconSystemName),
                                    // and computed execution for activation routing.
    let backgroundColor: String?
    let customIconName: String?
    let customIconImageName: String?   // carried to Presentation for cleanup/carry-through
    let customIconImageURL: URL?       // resolved absolute URL for AsyncImage; nil = no image
    let customLabel: String?
    let sliderOrientation: SliderOrientation   // slider cells only; how the control renders
}

/// Pixel dimensions of a source image, surfaced to the crop editor.
struct IconImageSizeResponse: Equatable, Sendable {
    let width: Int
    let height: Int
}

struct PadLayoutsResponse: Equatable, Sendable {
    let layouts: [PadLayoutResponse]
    let cells: [PadCellResponse]   // all cells across all layouts; filter by layoutID in ViewModel
}

// MARK: - Grid dimension bounds

extension PadLayoutResponse {
    /// Valid range for a pad's grid dimensions, re-exported from the Domain authority
    /// (`PadLayout.columnRange`/`rowRange`) so Presentation — which cannot import Domain —
    /// reads a single source instead of restating `1...8`. The authoritative validation
    /// stays in `RegisterPadLayoutRequest.validate()`.
    static let columnRange = PadLayout.columnRange
    static let rowRange = PadLayout.rowRange
}

// MARK: - Internal mapping helpers

extension PadLayoutResponse {
    init(from layout: PadLayout) {
        self.init(id: layout.id, name: layout.name,
                  columns: layout.columns, rows: layout.rows, sortIndex: layout.sortIndex)
    }
}

extension PadCellResponse {
    /// `iconsDirectory` is fetched once by `ReadPadLayoutsUseCase` and joined with the
    /// cell's stored filename to form the absolute URL Presentation renders.
    init(from cell: PadCell, entry: SavedEntryResponse?, iconsDirectory: URL?) {
        let url = cell.customIconImageName.flatMap { name in
            iconsDirectory?.appending(path: name)
        }
        self.init(
            id: cell.id, layoutID: cell.layoutID,
            column: cell.column, row: cell.row,
            columnSpan: cell.columnSpan, rowSpan: cell.rowSpan,
            entryID: cell.entryID, entry: entry,
            backgroundColor: cell.backgroundColor,
            customIconName: cell.customIconName,
            customIconImageName: cell.customIconImageName,
            customIconImageURL: url,
            customLabel: cell.customLabel,
            sliderOrientation: cell.sliderOrientation
        )
    }
}
