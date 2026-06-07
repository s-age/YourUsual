import Foundation

/// Generic installed-app resolution, backed by `InstalledAppStore` (the same
/// `NSWorkspace`/`Bundle` adapter the terminal settings use). Converts the
/// Infrastructure `AppInfoDTO` into the `BrowsedApp` entity. Holds no state.
final class InstalledAppRepository: InstalledAppRepositoryProtocol, Sendable {
    private let installedApps: any InstalledAppStoreProtocol

    init(installedApps: any InstalledAppStoreProtocol) {
        self.installedApps = installedApps
    }

    func resolveApp(at url: URL) -> BrowsedApp? {
        guard let info = installedApps.resolveApp(at: url) else { return nil }
        return BrowsedApp(bundleIdentifier: info.bundleIdentifier, name: info.name)
    }
}
