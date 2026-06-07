import Foundation

final class EditPadLayoutUseCase: AsyncUseCase, Sendable {
    private let padService: any PadServiceProtocol
    private let db: any DBProtocol

    init(padService: any PadServiceProtocol, db: any DBProtocol) {
        self.padService = padService
        self.db         = db
    }

    func execute(_ request: EditPadLayoutRequest) async throws -> PadLayoutResponse {
        let existing = try await padService.listAll()
        guard let current = existing.first(where: { $0.id == request.id }) else {
            throw OperationError.itemNotFound(id: request.id)
        }
        let cells = try await padService.list(forLayout: request.id)
        let updated = padService.updatingPadLayout(
            current,
            name: request.name,
            columns: request.columns,
            rows: request.rows
        )
        let prunedCells = padService.prunedCells(cells, forNewColumns: request.columns, newRows: request.rows)
        try await db.transaction { tx in
            try tx.editPadLayout(updated)
            try tx.replacePadCells(layoutID: updated.id, cells: prunedCells)
        }
        return PadLayoutResponse(from: updated)
    }
}
