import Foundation

final class ReorderEntriesUseCase: AsyncUseCase, Sendable {
    private let entries: any SavedEntryServiceProtocol
    private let db: any DBProtocol

    init(entries: any SavedEntryServiceProtocol, db: any DBProtocol) {
        self.entries = entries
        self.db = db
    }

    func execute(_ request: ReorderEntriesRequest) async throws {
        let current = try await entries.listAll()
        guard let items = entries.reordering(current, orderedIDs: request.orderedIDs) else { return }
        try await db.transaction { tx in try tx.replaceAllEntries(items) }
    }
}
