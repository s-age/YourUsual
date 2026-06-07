import Foundation

/// Resolves an installed app's icon file URL for display. A thin pass-through to the
/// Repository — there is no classification rule to apply (contrast
/// `TerminalSettingsService.resolveApp`, which classifies known/other). The only
/// "decision" — that a `.default` app choice has no specific icon — is the caller's,
/// since this is invoked only for an explicit `.app(bundleIdentifier:)`.
final class AppIconService: AppIconServiceProtocol, Sendable {
    private let repository: any AppIconRepositoryProtocol

    init(repository: any AppIconRepositoryProtocol) {
        self.repository = repository
    }

    func resolveIconFile(forBundleIdentifier bundleIdentifier: String) async throws -> URL? {
        try await repository.resolveIconFile(forBundleIdentifier: bundleIdentifier)
    }
}
