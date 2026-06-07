import Foundation

final class BrowseLauncherService: BrowseLauncherServiceProtocol, Sendable {
    private let launcher: any BrowseLauncherRepositoryProtocol

    init(launcher: any BrowseLauncherRepositoryProtocol) {
        self.launcher = launcher
    }

    func launch(_ entry: BrowseEntry) async throws {
        let bundleID: String?
        switch entry.app {
        case .default:                   bundleID = nil
        case .app(let bundleIdentifier): bundleID = bundleIdentifier
        }
        try await launcher.openPath(entry.url, withApp: bundleID)
    }
}
