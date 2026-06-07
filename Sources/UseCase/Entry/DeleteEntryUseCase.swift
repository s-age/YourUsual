import Foundation

final class DeleteEntryUseCase: AsyncUseCase, Sendable {
    private let entries: any SavedEntryServiceProtocol
    private let db: any DBProtocol

    init(entries: any SavedEntryServiceProtocol, db: any DBProtocol) {
        self.entries = entries
        self.db = db
    }

    func execute(_ request: DeleteEntryRequest) async throws {
        let current = try await entries.listAll()
        let items = try entries.deleting(current, id: request.id)
        try await db.transaction { tx in try tx.replaceAllEntries(items) }
    }
}
