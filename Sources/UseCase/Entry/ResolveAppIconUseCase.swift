import Foundation

/// Resolves the icon of the app a File/Directory entry opens with, as a cached PNG
/// file URL the Settings list renders via `AsyncImage(url:)`. Routing through the
/// UseCase → Domain Service → Repository → Infrastructure chain keeps the `NSWorkspace`
/// icon read + PNG encode in Infrastructure (`AppIconStore`) so they never reach the
/// SwiftUI layer. Returns nil when the bundle id resolves to no installed app — the
/// caller falls back to the folder SF Symbol.
final class ResolveAppIconUseCase: AsyncUseCase, Sendable {
    private let appIcons: any AppIconServiceProtocol

    init(appIcons: any AppIconServiceProtocol) {
        self.appIcons = appIcons
    }

    func execute(_ request: ResolveAppIconRequest) async throws -> URL? {
        try await appIcons.resolveIconFile(forBundleIdentifier: request.bundleIdentifier)
    }
}
