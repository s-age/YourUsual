import Foundation
import SwiftData

/// `layoutID` is a denormalized mirror of the `layout` relationship, stored so
/// `#Predicate` expressions can filter cells by UUID without traversing the
/// relationship (SwiftData predicates cannot follow to-one relationships in
/// `#Predicate` in some configurations; the denormalized column avoids this).
/// Both are set together — `layoutID` in the initialiser, `layout` in
/// `stageReplacePadCells` after fetching the parent — and must stay in sync.
@Model
final class PadCellModel {
    @Attribute(.unique) var id: UUID
    var layoutID: UUID        // denormalized for predicate queries
    var column: Int
    var row: Int
    var columnSpan: Int
    var rowSpan: Int
    var entryID: UUID?
    var backgroundColor: String?
    var customIconName: String?
    var customIconImageName: String?
    var customLabel: String?
    // Slider render orientation ("horizontal"/"vertical"); additive column with a literal
    // default so existing stores lightweight-migrate on open. Only slider cells consult it.
    var orientation: String = "horizontal"

    var layout: PadLayoutModel?   // inverse relationship (cascade parent)

    init(id: UUID, layoutID: UUID, column: Int, row: Int,
         columnSpan: Int, rowSpan: Int,
         entryID: UUID?, backgroundColor: String?,
         customIconName: String?, customIconImageName: String?,
         customLabel: String?, orientation: String = "horizontal") {
        self.id              = id
        self.layoutID        = layoutID
        self.column          = column
        self.row             = row
        self.columnSpan      = columnSpan
        self.rowSpan         = rowSpan
        self.entryID         = entryID
        self.backgroundColor = backgroundColor
        self.customIconName  = customIconName
        self.customIconImageName = customIconImageName
        self.customLabel     = customLabel
        self.orientation     = orientation
    }
}
