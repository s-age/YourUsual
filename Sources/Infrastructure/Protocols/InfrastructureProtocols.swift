import Foundation

protocol CategoryStoreProtocol: Sendable {
    func fetchAllCategories() async throws -> [CategoryDTO]   // sorted by sortIndex; empty when none
}

/// Persists the global command-output buffer setting (trailing lines of a background
/// command's output to retain).
protocol CommandOutputPreferenceStoreProtocol: Sendable {
    func loadBufferLines() -> Int?    // nil when never set (caller uses the default)
    func saveBufferLines(_ lines: Int)
}

/// Persists the global "usual" directory to a state file shared with the `your-usual cd` CLI.
/// Reads are tolerant and self-healing: a missing/empty/unreadable file falls back to the home
/// directory **and** rewrites the default initial state, so deleting the file recreates the
/// initial `cd "$HOME"` state on next access.
protocol CurrentDirectoryStoreProtocol: Sendable {
    /// Resolved absolute path of the usual directory. Never throws, never nil (self-heals to home).
    func loadPath() -> String
    /// Persist the usual directory. `nil`/blank resets to the default (home). Throws only on a
    /// genuine write failure (the substrate is a file).
    func savePath(_ path: String?) throws
}

/// Records non-fatal diagnostics — e.g. a persisted record that failed to decode
/// and was recovered/skipped — to the unified logging system. This is the port the
/// Repository layer uses so its data-recovery paths are *observable* instead of
/// silently swallowed; the Repository may not import `os` itself.
protocol DiagnosticsSinkProtocol: Sendable {
    func warning(_ message: String)
}

protocol EntryStoreProtocol: Sendable {
    func fetchAllEntries() async throws -> RegistryDTO   // sorted by sortIndex; empty items when none
}

/// Read-only access to the Pad SwiftData tables, surfacing DTOs to Repository.
protocol PadStoreProtocol: Sendable {
    func fetchAllLayouts() async throws -> [PadLayoutDTO]          // sorted by sortIndex
    func fetchAllCells(forLayout layoutID: UUID) async throws -> [PadCellDTO]
    func fetchAllCells() async throws -> [PadCellDTO]             // all cells across every layout
}

/// Reads and writes pad-icon image files (a substrate separate from the SwiftData
/// registry). Crops + downscales with ImageIO/CoreGraphics and stores PNGs under
/// Application Support. Methods are synchronous (blocking I/O); the caller offloads.
protocol PadIconStoreProtocol: Sendable {
    /// The storage directory, created if missing.
    func directory() throws -> URL
    /// Lightly reads a source image's pixel dimensions (properties only; no full decode).
    func probeSize(source: URL) throws -> PixelSizeDTO
    /// Crops `source` to the square at (`cropX`, `cropY`, side `side`), downscales to
    /// 512², writes a PNG, and returns the generated filename.
    func normalize(source: URL, cropX: Int, cropY: Int, side: Int) throws -> String
    /// Deletes a file (best-effort; a missing file does not throw).
    func delete(name: String) throws
}

struct PixelSizeDTO: Equatable, Sendable {
    let width: Int
    let height: Int
}

/// Resolves an installed app's icon to a cached PNG file URL (a filesystem image
/// substrate separate from the SwiftData registry, like `PadIconStore`). Synchronous,
/// blocking I/O (icon read + PNG encode + write); the Repository offloads. Returns nil
/// when the bundle id resolves to no installed app.
protocol AppIconStoreProtocol: Sendable {
    func resolveIconFile(forBundleIdentifier bundleIdentifier: String) throws -> URL?
}

/// Queries the system for installed applications. Used to decide which terminals
/// can be offered, and to resolve a browsed `.app` URL into its identity.
protocol InstalledAppStoreProtocol: Sendable {
    /// Whether an app with `bundleIdentifier` is installed.
    func isInstalled(bundleIdentifier: String) -> Bool
    /// Resolves a `.app` bundle URL into its bundle id + display name, or nil if not an app.
    func resolveApp(at url: URL) -> AppInfoDTO?
}

/// Reads filesystem facts the working-directory resolution depends on: the
/// current user's home directory and whether a URL points at a real directory.
protocol DirectoryProbeProtocol: Sendable {
    var homeDirectory: URL { get }
    func isDirectory(_ url: URL) -> Bool
}

/// Reads and writes the app's "launch at login" registration with the system.
protocol LoginItemStoreProtocol: Sendable {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

protocol NotifierProtocol: Sendable {
    func notify(title: String, body: String) async
}

protocol ProcessRunnerProtocol: Sendable {
    /// Runs the command and yields stdout/stderr incrementally, terminated by an
    /// `.exit` chunk. The stream is returned synchronously; a spawn failure is
    /// delivered as the stream's terminal error. `directories.currentDirectory` is
    /// injected into the child's environment as `YOUR_USUAL_CURRENT_DIRECTORY`,
    /// independent of `directories.workingDirectory` (where the process actually runs).
    func stream(commandLine: String,
                directories: CommandDirectoriesDTO) -> AsyncThrowingStream<CommandStreamChunkDTO, Error>
}

protocol LegacyRegistryReaderProtocol: Sendable {
    /// Reads the legacy `registry.json` into a transport `RegistryDTO`. Returns nil
    /// when no legacy file exists (fresh install); throws when a present file cannot
    /// be read or decoded. Pure transport read — it neither decides whether to import
    /// nor opens a transaction.
    func readLegacy() async throws -> RegistryDTO?
}

protocol RunHistoryStoreProtocol: Sendable {
    func fetch(forEntry id: UUID) async throws -> [RunRecordDTO]   // newest first
    func fetchAllRuns() async throws -> [RunRecordDTO]             // newest first
}

/// The transaction *mechanism* the store exposes upward (consumed by the
/// Repository `RegistryDatabaseGateway`, never by UseCase). One `transaction` is a single actor
/// hop that runs `body` inside one synchronous `modelContext.transaction`:
/// it commits once on success and rolls back if `body` throws. `body` receives
/// a `TxContextProtocol` whose **synchronous** staging primitives mutate the one
/// `modelContext` — this is the only place a mutation may be staged.
///
/// `body` is synchronous by hard SwiftData constraint: `ModelContext.transaction`
/// cannot span `await`. Resolve/validate/read *before* calling `transaction`; the
/// body only applies already-resolved writes. The store executes the commit but
/// never decides the boundary — that is the UseCase's via the Repository `RegistryDatabaseGateway`.
protocol TransactionRunnerProtocol: Sendable {
    func transaction<T: Sendable>(
        _ body: @Sendable (any TxContextProtocol) throws -> T
    ) async throws -> T
}

/// The synchronous staging primitives available *only* inside a
/// `TransactionRunnerProtocol.transaction` body. Each call stages a mutation on the
/// open transaction's `modelContext`; nothing here commits — the enclosing
/// `transaction` commits once when `body` returns. Reads/fetches are intentionally
/// absent: they belong before `transaction`, not inside the commit window.
///
/// The concrete witness (`RegistryDatabase`) is an `@ModelActor`, so the methods
/// are actor-isolated. The requirements are therefore declared `nonisolated` only
/// in shape; the body that calls them runs **on** the actor (it is invoked from
/// inside the actor-isolated `transaction`), so the calls are in-isolation. The
/// `@preconcurrency`/isolation is handled by passing the actor as the witness and
/// invoking synchronously within `transaction`.
protocol TxContextProtocol: Sendable {
    // RunHistory
    func stageInsertRun(_ run: RunRecordDTO) throws
    func stageDeleteRun(id: UUID) throws
    func stageDeleteAllRuns(forEntry id: UUID) throws
    func stageDeleteAllRuns() throws

    // Entry registry — whole-collection reconcile. `preservingIDs` are entries whose
    // stored row must be left **untouched** when it already exists (decode-recovery
    // placeholders: the incoming DTO is only a display shape, so overwriting it would
    // destroy the still-intact original row). A preserved id with no existing row is
    // inserted normally (e.g. a freshly imported placeholder — nothing to preserve).
    func stageReplaceAllEntries(_ dto: RegistryDTO, preservingIDs: Set<UUID>) throws

    // Category registry — whole-collection reconcile
    func stageReplaceAllCategories(_ dtos: [CategoryDTO]) throws

    // PadLayout staging — per-record
    func stageInsertPadLayout(_ dto: PadLayoutDTO) throws
    func stageUpdatePadLayout(_ dto: PadLayoutDTO) throws
    func stageDeletePadLayout(id: UUID) throws

    // PadCell staging — per-layout replacement
    func stageReplacePadCells(layoutID: UUID, cells: [PadCellDTO]) throws
}

protocol TerminalLauncherProtocol: Sendable {
    /// Runs `commandLine` in the terminal with `bundleIdentifier`, honouring
    /// `launchMode` (a `TerminalLaunchMode` raw value: "newWindow" / "newTab" /
    /// "reuse"). Unsupported terminals throw. `directories.currentDirectory` is exported
    /// as `YOUR_USUAL_CURRENT_DIRECTORY` ahead of the command (independent of
    /// `directories.workingDirectory`, where the command's shell `cd`s to).
    func run(commandLine: String, directories: CommandDirectoriesDTO,
             inTerminalBundleIdentifier bundleIdentifier: String,
             launchMode: String) async throws
}

/// Persists the reuse-mode window id per terminal, so a subsequent `reuse` launch
/// can target the same window. Only plain-integer ids (the form a terminal's
/// `window id` specifier expects) are stored or returned.
protocol ReuseWindowStoreProtocol: Sendable {
    func reuseWindowID(forTerminal bundleIdentifier: String) -> String?
    func setReuseWindowID(_ id: String, forTerminal bundleIdentifier: String)
}

/// Reads and writes the persisted global terminal preference.
protocol TerminalPreferenceStoreProtocol: Sendable {
    /// Returns the stored preference, `nil` when absent, or **throws** when a blob exists
    /// but cannot be JSON-decoded. Distinguishing corrupt from absent lets the Repository
    /// own the single recovery decision (reset/observe) instead of the store swallowing a
    /// corrupt blob to `nil` — indistinguishable from a fresh install.
    func load() throws -> TerminalPreferenceDTO?
    func save(_ dto: TerminalPreferenceDTO) throws
}

protocol WorkspaceLauncherProtocol: Sendable {
    /// Opens `path` with the app at `bundleIdentifier`, or the default app when nil.
    func open(path: URL, withAppBundleIdentifier bundleIdentifier: String?) async throws
}

protocol AppleScriptRunnerProtocol: Sendable {
    /// Compiles and runs `source` on the main thread. Returns the script's string
    /// result, or nil when the result descriptor has no string value.
    func run(source: String) async throws -> String?
}
