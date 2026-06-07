import AppKit
import Foundation

/// Resolves installed-app questions via `NSWorkspace` (same API used by
/// `WorkspaceLauncher`). Holds no state, so it is trivially `Sendable`.
final class InstalledAppStore: InstalledAppStoreProtocol, Sendable {
    func isInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    func resolveApp(at url: URL) -> AppInfoDTO? {
        guard let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        return AppInfoDTO(bundleIdentifier: identifier, name: name)
    }
}
