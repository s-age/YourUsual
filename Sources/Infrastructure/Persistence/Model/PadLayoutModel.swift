import Foundation
import SwiftData

@Model
final class PadLayoutModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var columns: Int
    var rows: Int
    var sortIndex: Int

    @Relationship(deleteRule: .cascade, inverse: \PadCellModel.layout)
    var cells: [PadCellModel] = []

    init(id: UUID, name: String, columns: Int, rows: Int, sortIndex: Int) {
        self.id        = id
        self.name      = name
        self.columns   = columns
        self.rows      = rows
        self.sortIndex = sortIndex
    }
}
