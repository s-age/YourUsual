import Foundation

final class RegisterPadLayoutUseCase: AsyncUseCase, Sendable {
    private let padService: any PadServiceProtocol
    private let db: any DBProtocol

    init(padService: any PadServiceProtocol, db: any DBProtocol) {
        self.padService = padService
        self.db         = db
    }

    func execute(_ request: RegisterPadLayoutRequest) async throws -> PadLayoutResponse {
        let existing = try await padService.listAll()
        let sortIndex = (existing.map(\.sortIndex).max() ?? -1) + 1
        let layout = padService.makePadLayout(
            name: request.name,
            columns: request.columns,
            rows: request.rows,
            sortIndex: sortIndex
        )
        try await db.transaction { tx in
            try tx.registerPadLayout(layout)
        }
        return PadLayoutResponse(from: layout)
    }
}
