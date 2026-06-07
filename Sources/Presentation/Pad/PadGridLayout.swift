import SwiftUI

// Each PadCellView passes its position + span via LayoutValueKey
struct PadCellPlacement: Equatable {
    let column: Int
    let row: Int
    let columnSpan: Int
    let rowSpan: Int
}

private struct PadCellPlacementKey: LayoutValueKey {
    static let defaultValue = PadCellPlacement(column: 0, row: 0, columnSpan: 1, rowSpan: 1)
}

extension View {
    func padCellPlacement(_ p: PadCellPlacement) -> some View {
        layoutValue(key: PadCellPlacementKey.self, value: p)
    }
}

/// A custom Layout that arranges children in a rows×columns grid, honouring
/// colspan and rowspan. Cell size = (totalWidth / columns) × (totalHeight / rows).
struct PadGridLayout: Layout {
    let columns: Int
    let rows: Int
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cellW = (bounds.width  - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let cellH = (bounds.height - spacing * CGFloat(rows - 1))    / CGFloat(rows)

        for subview in subviews {
            let p  = subview[PadCellPlacementKey.self]
            let w  = cellW * CGFloat(p.columnSpan) + spacing * CGFloat(p.columnSpan - 1)
            let h  = cellH * CGFloat(p.rowSpan)    + spacing * CGFloat(p.rowSpan - 1)
            let x  = bounds.minX + CGFloat(p.column) * (cellW + spacing)
            let y  = bounds.minY + CGFloat(p.row)    * (cellH + spacing)
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: w, height: h))
        }
    }
}
