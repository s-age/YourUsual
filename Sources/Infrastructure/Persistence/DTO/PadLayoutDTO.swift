import Foundation

struct PadLayoutDTO: Equatable, Sendable {
    let id: UUID
    var name: String
    var columns: Int
    var rows: Int
    var sortIndex: Int
}

struct PadCellDTO: Equatable, Sendable {
    let id: UUID
    let layoutID: UUID
    var column: Int
    var row: Int
    var columnSpan: Int
    var rowSpan: Int
    var entryID: UUID?
    var backgroundColor: String?
    var customIconName: String?
    var customIconImageName: String?
    var customLabel: String?
    var orientation: String = "horizontal"   // slider render orientation; ignored for buttons
}
