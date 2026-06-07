import Foundation

/// Owns the global terminal-settings intent: report the current preference, decide
/// which terminals are offered (Terminal always, iTerm2 only if installed), and
/// persist changes. The (app, mode) validity rule lives in `TerminalPreference`.
final class TerminalSettingsService: TerminalSettingsServiceProtocol, Sendable {
    private let repository: any TerminalSettingsRepositoryProtocol

    init(repository: any TerminalSettingsRepositoryProtocol) {
        self.repository = repository
    }

    func current() -> TerminalPreference {
        repository.loadPreference()
    }

    func availableTerminals() -> [TerminalAppSelection] {
        var apps: [TerminalAppSelection] = [.known(.terminal)]
        if repository.isInstalled(.iterm) {
            apps.append(.known(.iterm))
        }
        return apps
    }

    func setPreference(selection: TerminalAppSelection, launchMode: TerminalLaunchMode) throws
        -> TerminalPreference {
        // `TerminalPreference.init` clamps `launchMode` to one `selection` supports.
        let preference = TerminalPreference(selection: selection, launchMode: launchMode)
        try repository.savePreference(preference)
        return preference
    }

    func resolveApp(at url: URL) -> TerminalAppSelection? {
        guard let app = repository.resolveApp(at: url) else { return nil }
        // Domain rule: a browsed app is a *known* terminal iff its bundle id matches a
        // `TerminalApp` case (so we can drive it natively); otherwise it is `.other`.
        if let known = TerminalApp.allCases
            .first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            return .known(known)
        }
        return .other(bundleIdentifier: app.bundleIdentifier, name: app.name)
    }

    func normalizeStoredPreference() throws -> Bool {
        try repository.normalizeStoredPreference()
    }
}
