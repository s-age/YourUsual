import Foundation
import Observation

/// Shared, observable cache of resolved app-icon file URLs, keyed by bundle id.
///
/// One instance is created in `PresentationContainer` and injected into every screen
/// VM that lists entries (menu bar + settings), mirroring `RegistryViewModel`'s
/// single-source pattern. Sharing it means an icon resolved for one surface is reused
/// by the other — the same bundle id is never resolved (or rendered to PNG) twice — and
/// `@Observable` propagation re-renders any `body` reading a URL once it arrives.
@Observable
@MainActor
final class AppIconCache {
    private(set) var urls: [String: URL] = [:]
    private let resolveAppIcon: ResolveAppIconUseCaseProtocol

    init(resolveAppIcon: ResolveAppIconUseCaseProtocol) {
        self.resolveAppIcon = resolveAppIcon
    }

    /// File URL of the cached icon for an app, if resolved; nil falls back to the SF Symbol.
    func url(forBundleIdentifier bundleIdentifier: String) -> URL? {
        urls[bundleIdentifier]
    }

    /// Resolves (and caches) icon file URLs for every entry that opens with a specific
    /// app. Idempotent — already-cached bundle ids are skipped, so the menu and settings
    /// loads coalesce. Call from a VM's `load()` so `body` reads a populated cache rather
    /// than triggering resolution mid-render. A failure or uninstalled app leaves the
    /// entry on its folder SF Symbol.
    func resolve(for items: [SavedEntryResponse]) async {
        let bundleIDs = Set(items.compactMap(\.kind.appBundleIdentifier))
            .subtracting(urls.keys)
        for bundleID in bundleIDs {
            if let url = (try? await resolveAppIcon.execute(
                ResolveAppIconRequest(bundleIdentifier: bundleID))) ?? nil {
                urls[bundleID] = url
            }
        }
    }
}
