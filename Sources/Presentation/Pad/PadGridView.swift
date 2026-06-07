import SwiftUI

struct PadGridView: View {
    let layout: PadLayoutResponse
    let cells: [PadCellResponse]
    let isEditMode: Bool
    /// Passed straight through to each cell so a live slider cell can issue its drag intents.
    let viewModel: PadViewModel
    let onActivate: (PadCellResponse) -> Void
    let onEditCell: (PadCellResponse) -> Void
    let onDeleteCell: (PadCellResponse) -> Void
    let onEditEmptyCell: (Int, Int) -> Void       // column, row for new cell

    var body: some View {
        PadGridLayout(columns: layout.columns, rows: layout.rows, spacing: 6) {
            // Occupied cells
            ForEach(cells) { cell in
                PadCellView(
                    cell: cell,
                    isEditMode: isEditMode,
                    viewModel: viewModel,
                    onActivate: { onActivate(cell) },
                    onEdit: { onEditCell(cell) },
                    onDelete: { onDeleteCell(cell) }
                )
            }
            // Empty slots (edit mode only)
            if isEditMode {
                ForEach(emptySlots, id: \.self) { slot in
                    EmptyPadCellView(column: slot.column, row: slot.row) {
                        onEditEmptyCell(slot.column, slot.row)
                    }
                }
            }
        }
        .padding(8)
    }

    private struct Slot: Hashable { let column: Int; let row: Int }

    /// A square is empty when **no** cell's rectangle (origin + span) covers it.
    /// Using the full span means a 2×2 cell suppresses the "+" on all four squares.
    private var emptySlots: [Slot] {
        var slots: [Slot] = []
        for r in 0..<layout.rows {
            for c in 0..<layout.columns where !cells.contains(where: { covers($0, c, r) }) {
                slots.append(Slot(column: c, row: r))
            }
        }
        return slots
    }

    private func covers(_ cell: PadCellResponse, _ c: Int, _ r: Int) -> Bool {
        c >= cell.column && c < cell.column + cell.columnSpan &&
        r >= cell.row    && r < cell.row    + cell.rowSpan
    }
}

private struct EmptyPadCellView: View {
    let column: Int
    let row: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "plus")
                .font(.title2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padCellPlacement(PadCellPlacement(column: column, row: row, columnSpan: 1, rowSpan: 1))
    }
}
