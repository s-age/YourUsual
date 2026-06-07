import Foundation

/// Identity of a user-browsed `.app`, resolved from a file URL but **not yet
/// classified** as a known terminal (`Terminal.app`/iTerm2) or some other app.
///
/// The Repository returns this raw identity; deciding whether it maps to
/// `TerminalAppSelection.known` or `.other` is a domain rule and lives in
/// `TerminalSettingsService`.
struct BrowsedApp: Equatable, Sendable {
    let bundleIdentifier: String
    let name: String

    init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}
