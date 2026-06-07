import Foundation

final class DeletePadCellUseCase: AsyncUseCase, Sendable {
    private let padService: any PadServiceProtocol
    private let db: any DBProtocol

    init(padService: any PadServiceProtocol, db: any DBProtocol) {
        self.padService = padService
        self.db         = db
    }

    func execute(_ request: DeletePadCellRequest) async throws {
        let currentCells = try await padService.list(forLayout: request.layoutID)
        let updatedCells = padService.removingCell(at: request.column, row: request.row, from: currentCells)
        try await db.transaction { tx in
            try tx.replacePadCells(layoutID: request.layoutID, cells: updatedCells)
        }
        // Best-effort image cleanup after the commit (file I/O is outside the transaction).
        if let name = request.iconImageName {
            try? await padService.deleteIcon(name: name)
        }
    }
}
