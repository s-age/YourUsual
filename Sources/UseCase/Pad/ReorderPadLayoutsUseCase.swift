import Foundation

final class ReorderPadLayoutsUseCase: AsyncUseCase, Sendable {
    private let padService: any PadServiceProtocol
    private let db: any DBProtocol

    init(padService: any PadServiceProtocol, db: any DBProtocol) {
        self.padService = padService
        self.db         = db
    }

    func execute(_ request: ReorderPadLayoutsRequest) async throws {
        let current = try await padService.listAll()
        guard let result = padService.reordering(current, orderedIDs: request.orderedIDs) else { return }
        // PadLayout is a per-record substrate (no whole-blob `replaceAll`), so the
        // renumbered layouts are staged one edit each inside a single transaction —
        // one atomic unit, mirroring `ReorderCategoriesUseCase`'s `replaceAllCategories`.
        try await db.transaction { tx in
            for layout in result { try tx.editPadLayout(layout) }
        }
    }
}
