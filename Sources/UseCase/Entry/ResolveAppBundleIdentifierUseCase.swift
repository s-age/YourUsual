import Foundation

/// Resolves a picked `.app` URL to its bundle identifier for the file/browse entry
/// form. Routing this through the UseCase → Domain Service → Repository → Infrastructure
/// chain keeps the `Bundle(url:)` framework I/O in Infrastructure (`InstalledAppStore`),
/// mirroring the terminal-app browse path instead of reading the bundle in the View.
final class ResolveAppBundleIdentifierUseCase: SyncUseCase, Sendable {
    private let installedApps: any InstalledAppServiceProtocol

    init(installedApps: any InstalledAppServiceProtocol) {
        self.installedApps = installedApps
    }

    func execute(_ request: ResolveAppBundleIdentifierRequest) throws -> String? {
        installedApps.resolveApp(at: request.url)?.bundleIdentifier
    }
}
