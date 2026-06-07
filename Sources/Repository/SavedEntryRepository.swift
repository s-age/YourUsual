import Foundation

final class SavedEntryRepository: SavedEntryRepositoryProtocol, Sendable {
    private let store: any EntryStoreProtocol
    private let logger: any DiagnosticsSinkProtocol

    init(store: any EntryStoreProtocol, logger: any DiagnosticsSinkProtocol) {
        self.store = store
        self.logger = logger
    }

    func listAll() async throws -> [SavedEntry] {
        let dto = try await store.fetchAllEntries()
        // Transport recovery (shared with the legacy import path): a record whose kind
        // cannot be decoded must not fail the whole list — that would empty the menu and
        // make the app unoperable. Recover + log via RegistryEntryRecovery. Order is the
        // store's contract (sorted by sortIndex) and recovery preserves each row's index,
        // so the mapped result stays in order without re-sorting here.
        return dto.items
            .map { RegistryEntryRecovery.decodeOrRecover($0, noun: "registry entry", logger: logger) }
    }
}
