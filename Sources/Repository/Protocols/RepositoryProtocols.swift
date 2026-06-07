import Foundation

protocol CategoryRepositoryProtocol: Sendable {
    func listAll() async throws -> [EntryCategory]            // sorted by sortIndex
}

protocol FileSystemRepositoryProtocol: Sendable {
    func homeDirectory() -> URL
    func isDirectory(_ url: URL) -> Bool
}

protocol LaunchAtLoginRepositoryProtocol: Sendable {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

// Launching is split per execution concern (ISP): each behaviour service depends only on
// the verbs it actually drives, and each backing repository holds only the infrastructure
// adapter it needs — rather than one fat repository carrying every launch adapter.

protocol BrowseLauncherRepositoryProtocol: Sendable {
    func openPath(_ path: URL, withApp bundleIdentifier: String?) async throws
}

protocol CommandLauncherRepositoryProtocol: Sendable {
    func streamCommandInBackground(commandLine: String,
                                   directories: CommandDirectories) -> any AsyncSequence<CommandOutputEvent, Error>
    func runCommandInTerminal(commandLine: String,
                              directories: CommandDirectories,
                              bundleIdentifier: String,
                              launchMode: TerminalLaunchMode) async throws
}

/// Reads/writes the global current-directory value (file-backed, persisted; shared with the CLI).
protocol CurrentDirectoryRepositoryProtocol: Sendable {
    func loadPreference() -> CurrentDirectoryPreference
    func savePreference(_ preference: CurrentDirectoryPreference) throws
}

protocol AppleScriptLauncherRepositoryProtocol: Sendable {
    /// Compiles and runs `source` on the main thread. Returns the script's string
    /// result, or nil when the script produces no string value.
    func runAppleScript(source: String) async throws -> String?
}

protocol NotifierRepositoryProtocol: Sendable {
    func notify(title: String, body: String) async
}

protocol RunHistoryRepositoryProtocol: Sendable {
    func list(forEntry id: UUID) async throws -> [RunRecord]   // newest first
    func listAll() async throws -> [RunRecord]                 // newest first
}

protocol SavedEntryRepositoryProtocol: Sendable {
    func listAll() async throws -> [SavedEntry]           // sorted by sortIndex
}

protocol CommandOutputSettingsRepositoryProtocol: Sendable {
    func loadPreference() -> CommandOutputPreference
    func savePreference(_ preference: CommandOutputPreference)
}

protocol LegacyRegistryRepositoryProtocol: Sendable {
    /// Lists the legacy `registry.json` as domain entities, or nil when no legacy
    /// file exists. Undecodable records are recovered (and logged), mirroring
    /// `SavedEntryRepository`. Whether to actually import is the Domain's decision.
    func listLegacy() async throws -> [SavedEntry]?
}

protocol TerminalSettingsRepositoryProtocol: Sendable {
    func loadPreference() -> TerminalPreference
    func savePreference(_ preference: TerminalPreference) throws
    /// One-shot startup hygiene: rewrites the stored preference to its canonical form so
    /// `loadPreference()` stops re-warning on every call, returning whether a write
    /// occurred. Two non-canonical cases are handled (both logged): an undecodable blob is
    /// reset to `.default`; a decodable blob whose `launchMode` was present-but-unparseable
    /// is rewritten with the **selection kept** and the mode coerced to default. A valid,
    /// fully-canonical or absent blob is left untouched.
    func normalizeStoredPreference() throws -> Bool
    /// Whether a known terminal is installed on this machine.
    func isInstalled(_ app: TerminalApp) -> Bool
    /// Resolves a browsed `.app` URL into its raw identity (bundle id + name), or nil
    /// if it is not an app. Classifying it into `.known` vs `.other` is a domain rule
    /// and belongs to `TerminalSettingsService`, not here.
    func resolveApp(at url: URL) -> BrowsedApp?
}

protocol PadLayoutRepositoryProtocol: Sendable {
    func listAll() async throws -> [PadLayout]
}

protocol PadCellRepositoryProtocol: Sendable {
    func list(forLayout layoutID: UUID) async throws -> [PadCell]
    func listAll() async throws -> [PadCell]
}

/// Pad-icon image storage on the filesystem (a substrate separate from the SwiftData
/// registry, so its reads/writes live outside `transaction`). Backed by the
/// Infrastructure `PadIconStore`; the concrete implementation is a separate unit.
protocol PadIconRepositoryProtocol: Sendable {
    /// The directory where pad-icon PNGs are stored.
    func directory() async throws -> URL
    /// Lightly probes a source image's pixel dimensions (without fully decoding it).
    func probeSize(source: URL) async throws -> PixelSize
    /// Crops `source`, downscales to 512², saves a PNG, and returns the generated filename.
    func importIcon(source: URL, crop: IconCrop) async throws -> String
    /// Deletes an icon PNG (best-effort; a missing file is not an error).
    func deleteIcon(name: String) async throws
}

/// Resolves a picked `.app` URL into its installed-app identity, backed by the same
/// `InstalledAppStore` the terminal settings use. The generic (non-terminal) path: the
/// file/browse entry form needs the identity of the app the user picked to open a path
/// with, without any terminal classification.
protocol InstalledAppRepositoryProtocol: Sendable {
    /// Bundle id + name of the app at `url`, or nil if it is not a readable `.app`.
    func resolveApp(at url: URL) -> BrowsedApp?
}

/// Resolves an installed app's icon to a cached PNG file URL, backed by the
/// Infrastructure `AppIconStore` (a filesystem image substrate, outside `transaction`).
protocol AppIconRepositoryProtocol: Sendable {
    func resolveIconFile(forBundleIdentifier bundleIdentifier: String) async throws -> URL?
}
