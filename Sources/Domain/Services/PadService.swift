import Foundation

final class PadService: PadServiceProtocol, Sendable {
    private let layoutRepository: any PadLayoutRepositoryProtocol
    private let cellRepository: any PadCellRepositoryProtocol
    private let iconRepository: any PadIconRepositoryProtocol

    init(layoutRepository: any PadLayoutRepositoryProtocol,
         cellRepository: any PadCellRepositoryProtocol,
         iconRepository: any PadIconRepositoryProtocol) {
        self.layoutRepository = layoutRepository
        self.cellRepository   = cellRepository
        self.iconRepository   = iconRepository
    }

    func listAll() async throws -> [PadLayout] {
        try await layoutRepository.listAll()
    }

    func list(forLayout layoutID: UUID) async throws -> [PadCell] {
        try await cellRepository.list(forLayout: layoutID)
    }

    func listAllCells() async throws -> [PadCell] {
        try await cellRepository.listAll()
    }

    func makePadLayout(name: String, columns: Int, rows: Int, sortIndex: Int) -> PadLayout {
        // Normalize for storage; non-empty validation runs upstream in the Request.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return PadLayout.create(name: trimmed, columns: columns, rows: rows, sortIndex: sortIndex)
    }

    func updatingPadLayout(_ layout: PadLayout, name: String, columns: Int, rows: Int) -> PadLayout {
        // Normalize for storage; non-empty validation runs upstream in the Request.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return layout.applying(name: trimmed, columns: columns, rows: rows)
    }

    func reordering(_ current: [PadLayout], orderedIDs: [UUID]) -> [PadLayout]? {
        // `reduce(into:)` (not `Dictionary(uniqueKeysWithValues:)`) so a corrupt/legacy
        // store carrying a duplicate id can't trap — mirrors `CategoryService.reordering`.
        let byID = current.reduce(into: [UUID: PadLayout]()) { $0[$1.id] = $1 }
        let ordered = orderedIDs.compactMap { byID[$0] }
        guard ordered.count > 1 else { return nil }
        // Keep any layouts the caller didn't mention at the end, in their current order,
        // then renumber the whole list 0..n.
        let mentioned = Set(orderedIDs)
        var result = ordered + current.filter { !mentioned.contains($0.id) }
        for index in result.indices {
            result[index].sortIndex = index
        }
        return result
    }

    func makePadCell(layoutID: UUID, draft: PadCellDraft, fitting layout: PadLayout,
                     linkedEntryKind: EntryKind?) throws -> PadCell {
        // A slider needs span along its long axis and is pinned to one cell on its short
        // axis: a horizontal slider needs ≥2 columns and a single row; a vertical slider
        // needs ≥2 rows and a single column. A button (nil / any other kind) is unconstrained.
        // Whether the cell *is* a slider follows the linked entry's kind; *which way* it runs
        // is the cell's own choice (`draft.sliderOrientation`), so the same command can be
        // placed either orientation.
        let sliderOrientation: SliderOrientation?
        if case .slider = linkedEntryKind { sliderOrientation = draft.sliderOrientation }
        else { sliderOrientation = nil }

        // The UI offers the matching lower bound, but re-validate here so the rule holds
        // regardless of caller (UI clamp + Domain validation, two layers).
        if sliderOrientation == .horizontal, draft.columnSpan < 2 {
            throw OperationError.invalidItem(reason: "A slider needs at least 2 columns of width")
        }
        if sliderOrientation == .vertical, draft.rowSpan < 2 {
            throw OperationError.invalidItem(reason: "A slider needs at least 2 rows of height")
        }

        let columnSpan: Int
        let rowSpan: Int
        switch sliderOrientation {
        case .horizontal: columnSpan = max(2, draft.columnSpan); rowSpan = 1
        case .vertical:   columnSpan = 1;                        rowSpan = max(2, draft.rowSpan)
        case nil:         columnSpan = max(1, draft.columnSpan); rowSpan = max(1, draft.rowSpan)
        }
        let isSlider = sliderOrientation != nil

        let cell = PadCell(
            id: UUID(), layoutID: layoutID,
            column: draft.column, row: draft.row,
            columnSpan: columnSpan, rowSpan: rowSpan,
            entryID: draft.entryID,
            backgroundColor: draft.backgroundColor,
            // A slider carries no icon/label (the UI omits them, but drop them here too).
            customIconName: isSlider ? nil : draft.customIconName,
            customIconImageName: isSlider ? nil : draft.customIconImageName,
            customLabel: isSlider ? nil : draft.customLabel,
            sliderOrientation: draft.sliderOrientation
        )
        guard cell.fits(inColumns: layout.columns, rows: layout.rows) else {
            throw OperationError.invalidItem(reason: "Cell span overflows grid bounds")
        }
        return cell
    }

    func prunedCells(_ cells: [PadCell], forNewColumns columns: Int, newRows rows: Int) -> [PadCell] {
        cells.filter { $0.fits(inColumns: columns, rows: rows) }
    }

    func applyingCellChange(_ cells: [PadCell], newCell: PadCell) throws -> [PadCell] {
        // Exclude the cell being replaced (same origin), then reject any overlap with
        // a *different* cell — growing a span must not collide with a neighbour.
        let others = cells.filter { $0.column != newCell.column || $0.row != newCell.row }
        if let clash = others.first(where: { $0.overlaps(newCell) }) {
            throw OperationError.invalidItem(
                reason: "Cell at (\(newCell.column),\(newCell.row)) overlaps the cell at (\(clash.column),\(clash.row))"
            )
        }
        return others + [newCell]
    }

    func removingCell(at column: Int, row: Int, from cells: [PadCell]) -> [PadCell] {
        cells.filter { $0.column != column || $0.row != row }
    }

    func iconsDirectory() async throws -> URL {
        try await iconRepository.directory()
    }

    func probeIconSize(source: URL) async throws -> PixelSize {
        try await iconRepository.probeSize(source: source)
    }

    func importIcon(source: URL, crop: IconCrop) async throws -> String {
        try await iconRepository.importIcon(source: source, crop: crop)
    }

    func deleteIcon(name: String) async throws {
        try await iconRepository.deleteIcon(name: name)
    }
}
