import Foundation

final class RunHistoryRepository: RunHistoryRepositoryProtocol, Sendable {
    private let store: any RunHistoryStoreProtocol
    private let logger: any DiagnosticsSinkProtocol

    init(store: any RunHistoryStoreProtocol, logger: any DiagnosticsSinkProtocol) {
        self.store = store
        self.logger = logger
    }

    // Ordering (newest-first) is the store's contract — its `SortDescriptor(\.executedAt)`
    // must run *before* the fetch cap, so it cannot move up here — and `compactMap`
    // preserves that order. This mirrors the entry/category repositories, which likewise
    // trust the store's `sortIndex` order rather than re-sorting.
    func list(forEntry id: UUID) async throws -> [RunRecord] {
        try await store.fetch(forEntry: id).compactMap(decodeOrSkip)
    }

    func listAll() async throws -> [RunRecord] {
        try await store.fetchAllRuns().compactMap(decodeOrSkip)
    }

    /// Transport recovery: a run-history record is an append-only log line with no
    /// meaningful default outcome, so a record whose outcome can't be decoded is
    /// skipped (treated as absent) rather than throwing and losing the whole history.
    /// The skip is **logged** so corruption is observable, not silently swallowed.
    private func decodeOrSkip(_ dto: RunRecordDTO) -> RunRecord? {
        do {
            return try RunRecordMapper.toEntity(dto)
        } catch {
            logger.warning(
                "run-history record \(dto.id) failed to decode (\(error.localizedDescription)); skipped"
            )
            return nil
        }
    }
}
