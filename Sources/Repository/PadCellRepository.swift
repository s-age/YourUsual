import Foundation

final class PadCellRepository: PadCellRepositoryProtocol, Sendable {
    private let store: any PadStoreProtocol

    init(store: any PadStoreProtocol) {
        self.store = store
    }

    func list(forLayout layoutID: UUID) async throws -> [PadCell] {
        try await store.fetchAllCells(forLayout: layoutID).map(PadMapper.toEntity)
    }

    func listAll() async throws -> [PadCell] {
        try await store.fetchAllCells().map(PadMapper.toEntity)
    }
}
