import Foundation

final class SavePadCellUseCase: AsyncUseCase, Sendable {
    private let padService: any PadServiceProtocol
    private let entries: any SavedEntryServiceProtocol
    private let db: any DBProtocol

    init(
        padService: any PadServiceProtocol,
        entries: any SavedEntryServiceProtocol,
        db: any DBProtocol
    ) {
        self.padService = padService
        self.entries    = entries
        self.db         = db
    }

    func execute(_ request: SavePadCellRequest) async throws {
        let layouts = try await padService.listAll()
        guard let layout = layouts.first(where: { $0.id == request.layoutID }) else {
            throw OperationError.itemNotFound(id: request.layoutID)
        }
        let currentCells = try await padService.list(forLayout: request.layoutID)

        // Resolve the linked entry's kind so `makePadCell` can apply the slider geometry
        // rules. An unlinked cell — or a stale entryID — is treated as a button (nil).
        let linkedKind: EntryKind?
        if let entryID = request.entryID {
            let all = try await entries.listAll()
            linkedKind = all.first(where: { $0.id == entryID })?.kind
        } else {
            linkedKind = nil
        }

        // 1) Import the new image *before* the transaction (file I/O is a separate
        //    substrate, outside `db.transaction`). Unchanged ⇒ carry the existing name.
        var imageName = request.customIconImageName
        if let path = request.newIconSourcePath, let crop = request.newIconCrop {
            imageName = try await padService.importIcon(source: URL(filePath: path), crop: crop.toDomain)
        }

        // 2) Commit the cell row inside the transaction.
        let draft = PadCellDraft(
            column: request.column, row: request.row,
            columnSpan: request.columnSpan, rowSpan: request.rowSpan,
            entryID: request.entryID,
            backgroundColor: request.backgroundColor,
            customIconName: request.customIconName,
            customIconImageName: imageName,
            customLabel: request.customLabel,
            sliderOrientation: request.sliderOrientation
        )
        let newCell = try padService.makePadCell(
            layoutID: request.layoutID, draft: draft, fitting: layout, linkedEntryKind: linkedKind
        )
        let updatedCells = try padService.applyingCellChange(currentCells, newCell: newCell)
        try await db.transaction { tx in
            try tx.replacePadCells(layoutID: request.layoutID, cells: updatedCells)
        }

        // 3) Clean up the superseded image *after* the commit (best-effort). A failure
        //    here only leaves a harmless orphan PNG.
        if let old = request.previousIconImageName, old != imageName {
            try? await padService.deleteIcon(name: old)
        }
    }
}
