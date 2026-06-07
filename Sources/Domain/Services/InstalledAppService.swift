import Foundation

/// Resolves a picked `.app` URL to its installed-app identity. This is the seam that
/// lets the UseCase reach installed-app resolution without touching the Repository
/// directly. It is a thin pass-through by design: the file/browse form needs only the
/// raw identity, so there is no classification rule to apply here (contrast
/// `TerminalSettingsService.resolveApp`, which classifies into known/other).
final class InstalledAppService: InstalledAppServiceProtocol, Sendable {
    private let repository: any InstalledAppRepositoryProtocol

    init(repository: any InstalledAppRepositoryProtocol) {
        self.repository = repository
    }

    func resolveApp(at url: URL) -> BrowsedApp? {
        repository.resolveApp(at: url)
    }
}
