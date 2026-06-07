import Foundation

/// Opens a path with the default or a chosen app, backing `BrowseLauncherService`.
final class BrowseLauncherRepository: BrowseLauncherRepositoryProtocol, Sendable {
    private let workspace: any WorkspaceLauncherProtocol

    init(workspace: any WorkspaceLauncherProtocol) {
        self.workspace = workspace
    }

    func openPath(_ path: URL, withApp bundleIdentifier: String?) async throws {
        try await workspace.open(path: path, withAppBundleIdentifier: bundleIdentifier)
    }
}
