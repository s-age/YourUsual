import Foundation

final class ReadEntriesUseCase: AsyncUseCase, Sendable {
    private let entries: any SavedEntryServiceProtocol

    init(entries: any SavedEntryServiceProtocol) {
        self.entries = entries
    }

    func execute(_ request: ReadEntriesRequest) async throws -> [SavedEntryResponse] {
        let items = try await entries.listAll()
        return items.map(SavedEntryResponse.init(from:))
    }
}
