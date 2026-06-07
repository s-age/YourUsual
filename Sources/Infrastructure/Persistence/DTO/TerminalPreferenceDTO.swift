import Foundation

/// Persisted shape of the global terminal preference (JSON in `UserDefaults`).
/// `kind` discriminates the selection: `"known"` uses `app` (a `TerminalApp`
/// raw value); `"other"` uses `bundleIdentifier` + `name`.
///
/// `launchMode` is `Optional` on purpose: it was added after the first shipped shape,
/// so a blob saved before it existed has no `launchMode` key. Keeping it optional lets
/// such an old-but-valid blob still JSON-decode (the mapper falls a missing/unknown mode
/// back to `.default`), instead of failing decode and being mistaken for corruption.
/// `kind` stays required — a blob without it carries no selection and *is* corrupt.
struct TerminalPreferenceDTO: Codable, Sendable {
    var kind: String
    var app: String?
    var bundleIdentifier: String?
    var name: String?
    var launchMode: String?
}
