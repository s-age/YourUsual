import Foundation
import SwiftData

// PadStore read conformance lives in its own extension to keep the actor body
// within the type-length budget. `modelContext` is provided by `@ModelActor` on
// the main declaration and is reachable from this same-module extension. Reads
// only — writes are staged inside `transaction` (see RegistryDatabase+Transaction).
extension RegistryDatabase: PadStoreProtocol {

    func fetchAllLayouts() throws -> [PadLayoutDTO] {
        let descriptor = FetchDescriptor<PadLayoutModel>(
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        return try modelContext.fetch(descriptor).map(Self.toLayoutDTO)
    }

    func fetchAllCells(forLayout layoutID: UUID) throws -> [PadCellDTO] {
        let lid = layoutID
        let descriptor = FetchDescriptor<PadCellModel>(
            predicate: #Predicate { $0.layoutID == lid }
        )
        return try modelContext.fetch(descriptor).map(Self.toCellDTO)
    }

    func fetchAllCells() throws -> [PadCellDTO] {
        try modelContext.fetch(FetchDescriptor<PadCellModel>()).map(Self.toCellDTO)
    }

    // MARK: - Private @Model → DTO conversions (@Model must not escape the actor)

    private static func toLayoutDTO(_ m: PadLayoutModel) -> PadLayoutDTO {
        PadLayoutDTO(id: m.id, name: m.name, columns: m.columns, rows: m.rows, sortIndex: m.sortIndex)
    }

    private static func toCellDTO(_ m: PadCellModel) -> PadCellDTO {
        PadCellDTO(
            id: m.id, layoutID: m.layoutID,
            column: m.column, row: m.row,
            columnSpan: m.columnSpan, rowSpan: m.rowSpan,
            entryID: m.entryID,
            backgroundColor: m.backgroundColor,
            customIconName: m.customIconName,
            customIconImageName: m.customIconImageName,
            customLabel: m.customLabel,
            orientation: m.orientation
        )
    }
}
