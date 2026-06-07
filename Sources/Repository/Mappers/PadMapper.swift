import Foundation

/// Single source of truth for PadLayout and PadCell DTO ↔ entity conversions. Both
/// the read path (repositories) and the write path (TxAdapter) route through this
/// mapper so the round-trip cannot drift.
enum PadMapper {

    // MARK: - PadLayout

    static func toEntity(_ dto: PadLayoutDTO) -> PadLayout {
        PadLayout(
            id: dto.id,
            name: dto.name,
            columns: dto.columns,
            rows: dto.rows,
            sortIndex: dto.sortIndex
        )
    }

    static func toDTO(_ layout: PadLayout) -> PadLayoutDTO {
        PadLayoutDTO(
            id: layout.id,
            name: layout.name,
            columns: layout.columns,
            rows: layout.rows,
            sortIndex: layout.sortIndex
        )
    }

    // MARK: - PadCell

    static func toEntity(_ dto: PadCellDTO) -> PadCell {
        PadCell(
            id: dto.id,
            layoutID: dto.layoutID,
            column: dto.column,
            row: dto.row,
            columnSpan: dto.columnSpan,
            rowSpan: dto.rowSpan,
            entryID: dto.entryID,
            backgroundColor: dto.backgroundColor,
            customIconName: dto.customIconName,
            customIconImageName: dto.customIconImageName,
            customLabel: dto.customLabel,
            // Unknown/legacy raw strings decode as horizontal.
            sliderOrientation: SliderOrientation(rawValue: dto.orientation) ?? .horizontal
        )
    }

    static func toDTO(_ cell: PadCell) -> PadCellDTO {
        PadCellDTO(
            id: cell.id,
            layoutID: cell.layoutID,
            column: cell.column,
            row: cell.row,
            columnSpan: cell.columnSpan,
            rowSpan: cell.rowSpan,
            entryID: cell.entryID,
            backgroundColor: cell.backgroundColor,
            customIconName: cell.customIconName,
            customIconImageName: cell.customIconImageName,
            customLabel: cell.customLabel,
            orientation: cell.sliderOrientation.rawValue
        )
    }
}
