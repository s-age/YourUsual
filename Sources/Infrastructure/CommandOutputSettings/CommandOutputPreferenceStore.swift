import Foundation

/// Persists the command-output buffer size (trailing lines to retain) under a single
/// `UserDefaults` key. Stateless (reads `.standard` per call), so it is trivially
/// `Sendable`.
final class CommandOutputPreferenceStore: CommandOutputPreferenceStoreProtocol, Sendable {
    private static let key = "commandOutputBufferLines"

    func loadBufferLines() -> Int? {
        // `object(forKey:)` distinguishes "never set" (nil → caller uses the default)
        // from a stored value, so an explicit value is honoured while a fresh install
        // falls back to the default.
        guard UserDefaults.standard.object(forKey: Self.key) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: Self.key)
    }

    /// Non-throwing by design: writing an `Int` to `UserDefaults` is a property-list
    /// primitive that cannot fail (no encoding step that could error). If this ever
    /// grows an encoding step that *can* fail, make it `throws` rather than swallowing
    /// the failure — a silent save-drop is exactly the failure mode we avoid elsewhere.
    func saveBufferLines(_ lines: Int) {
        UserDefaults.standard.set(lines, forKey: Self.key)
    }
}
