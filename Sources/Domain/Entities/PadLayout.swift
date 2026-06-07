import Foundation

struct PadLayout: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var columns: Int    // 1–8; validated by RegisterPadLayoutRequest.validate()
    var rows: Int       // 1–8
    var sortIndex: Int

    static let columnRange = 1...8
    static let rowRange    = 1...8

    static func create(name: String, columns: Int, rows: Int, sortIndex: Int) -> PadLayout {
        PadLayout(id: UUID(), name: name, columns: columns, rows: rows, sortIndex: sortIndex)
    }

    func applying(name: String, columns: Int, rows: Int) -> PadLayout {
        var updated = self
        updated.name    = name
        updated.columns = columns
        updated.rows    = rows
        return updated
    }
}
