import Foundation

final class PadLayoutRepository: PadLayoutRepositoryProtocol, Sendable {
    private let store: any PadStoreProtocol

    init(store: any PadStoreProtocol) {
        self.store = store
    }

    func listAll() async throws -> [PadLayout] {
        try await store.fetchAllLayouts().map(PadMapper.toEntity)
    }
}
