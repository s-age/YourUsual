import Foundation

final class DeletePadLayoutUseCase: AsyncUseCase, Sendable {
    private let db: any DBProtocol

    init(db: any DBProtocol) { self.db = db }

    func execute(_ request: DeletePadLayoutRequest) async throws {
        try await db.transaction { tx in
            try tx.deletePadLayout(id: request.id)
            // SwiftData cascade deletes cells via PadLayoutModel.cells relationship.
            // No separate replacePadCells call needed.
        }
    }
}
