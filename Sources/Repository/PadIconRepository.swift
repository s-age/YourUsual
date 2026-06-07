import Foundation

/// Bridges the Domain `PadServiceProtocol` icon verbs to the Infrastructure
/// `PadIconStore`, translating transport types (`PixelSizeDTO` → `PixelSize`) and
/// decomposing the `IconCrop` entity into the store's pixel-integer primitives. A
/// DataSource-style repository: no SwiftData, no `@Model`.
///
/// The store's `probeSize`/`normalize` are synchronous, blocking I/O (file read +
/// image decode/encode). They are offloaded here with `Task.detached(priority:)` so
/// the cooperative pool is not stalled — per the Infrastructure offload policy.
final class PadIconRepository: PadIconRepositoryProtocol, Sendable {
    private let store: any PadIconStoreProtocol

    init(store: any PadIconStoreProtocol) {
        self.store = store
    }

    func directory() async throws -> URL {
        try store.directory()
    }

    func probeSize(source: URL) async throws -> PixelSize {
        let dto = try await Task.detached(priority: .userInitiated) {
            try self.store.probeSize(source: source)
        }.value
        return PixelSize(width: dto.width, height: dto.height)
    }

    func importIcon(source: URL, crop: IconCrop) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try self.store.normalize(source: source,
                                     cropX: crop.originX, cropY: crop.originY, side: crop.side)
        }.value
    }

    func deleteIcon(name: String) async throws {
        try store.delete(name: name)
    }
}
