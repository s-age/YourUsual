import Foundation

/// Identifiable input for the cell editor sheet (`PadCellEditSheet`), driving
/// `.sheet(item:)`. Carries the target layout plus the grid origin being edited,
/// and the existing cell (nil for a new placement). Shared by the launcher panel's
/// host and the Settings "Pads" editor.
struct PadCellEditContext: Identifiable {
    let id = UUID()
    let layout: PadLayoutResponse
    let column: Int
    let row: Int
    let existing: PadCellResponse?

    init(layout: PadLayoutResponse, existing: PadCellResponse?) {
        self.layout   = layout
        self.column   = existing?.column ?? 0
        self.row      = existing?.row ?? 0
        self.existing = existing
    }

    init(layout: PadLayoutResponse, column: Int, row: Int, existing: PadCellResponse?) {
        self.layout   = layout
        self.column   = column
        self.row      = row
        self.existing = existing
    }
}
