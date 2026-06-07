import Foundation

/// Resolves an installed app's icon to a cached PNG file URL, backed by the
/// Infrastructure `AppIconStore`. The store's `resolveIconFile` is synchronous, blocking I/O
/// (icon read + PNG encode + write), offloaded here with `Task.detached(priority:)` so
/// the cooperative pool is not stalled — per the Infrastructure offload policy. A
/// DataSource-style repository: no SwiftData, holds no state.
final class AppIconRepository: AppIconRepositoryProtocol, Sendable {
    private let store: any AppIconStoreProtocol

    init(store: any AppIconStoreProtocol) {
        self.store = store
    }

    func resolveIconFile(forBundleIdentifier bundleIdentifier: String) async throws -> URL? {
        try await Task.detached(priority: .userInitiated) {
            try self.store.resolveIconFile(forBundleIdentifier: bundleIdentifier)
        }.value
    }
}
