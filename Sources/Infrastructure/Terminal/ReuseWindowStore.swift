import Foundation

/// Persists the reuse-mode window id per terminal under a `UserDefaults` key.
/// Stateless (reads `.standard` per call), so it is trivially `Sendable`.
///
/// Only plain-integer ids are stored or returned: that is the form both terminals'
/// `window id` specifiers expect, and validating it keeps a malformed value from
/// being spliced into the AppleScript source.
///
/// Validation uses `Int(_:)` rather than `allSatisfy(\.isNumber)`: the latter also
/// accepts non-ASCII Unicode digits (`²`, `٥`, `½`), whereas `Int(_:)` matches the
/// "plain integer" intent exactly — the tightest guard against splicing anything but
/// an ASCII integer into the script source.
final class ReuseWindowStore: ReuseWindowStoreProtocol, Sendable {
    private static func key(_ bundleIdentifier: String) -> String {
        "terminalReuseWindowID.\(bundleIdentifier)"
    }

    func reuseWindowID(forTerminal bundleIdentifier: String) -> String? {
        guard let raw = UserDefaults.standard.string(forKey: Self.key(bundleIdentifier)),
              Int(raw) != nil else { return nil }
        return raw
    }

    func setReuseWindowID(_ id: String, forTerminal bundleIdentifier: String) {
        guard Int(id) != nil else { return }
        UserDefaults.standard.set(id, forKey: Self.key(bundleIdentifier))
    }
}
