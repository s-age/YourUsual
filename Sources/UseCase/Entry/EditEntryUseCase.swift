import Foundation

final class EditEntryUseCase: AsyncUseCase, Sendable {
    private let entries: any SavedEntryServiceProtocol
    private let db: any DBProtocol

    init(entries: any SavedEntryServiceProtocol, db: any DBProtocol) {
        self.entries = entries
        self.db = db
    }

    func execute(_ request: EditEntryRequest) async throws -> SavedEntryResponse {
        let current = try await entries.listAll()
        let result = try entries.editing(
            current, id: request.id,
            edit: SavedEntryEdit(
                name: request.name, kind: request.kind.toDomain,
                isHiddenFromMenuBar: request.isHiddenFromMenuBar
            )
        )
        try await db.transaction { tx in try tx.replaceAllEntries(result.items) }
        return SavedEntryResponse(from: result.edited)
    }
}
