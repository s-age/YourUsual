import Foundation

final class RegisterEntryUseCase: AsyncUseCase, Sendable {
    private let entries: any SavedEntryServiceProtocol
    private let db: any DBProtocol

    init(entries: any SavedEntryServiceProtocol, db: any DBProtocol) {
        self.entries = entries
        self.db = db
    }

    func execute(_ request: RegisterEntryRequest) async throws -> SavedEntryResponse {
        let current = try await entries.listAll()
        let result = entries.registering(
            current, name: request.name, kind: request.kind.toDomain, categoryID: request.categoryID
        )
        try await db.transaction { tx in try tx.replaceAllEntries(result.items) }
        return SavedEntryResponse(from: result.registered)
    }
}
