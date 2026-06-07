import Foundation

protocol AppleScriptRunnerServiceProtocol: Sendable {
    /// Runs the AppleScript source and returns its string result, or nil when the
    /// script produces no string value.
    func run(_ entry: AppleScriptEntry) async throws -> String?
}

protocol BrowseLauncherServiceProtocol: Sendable {
    func launch(_ entry: BrowseEntry) async throws
}

protocol CategoryServiceProtocol: Sendable {
    func listAll() async throws -> [EntryCategory]

    /// Seeds the built-in Default category as the empty-state fallback, but only
    /// when no categories exist at all. Returns the categories to persist, or
    /// `nil` (no-op) when at least one category is already present — so deleting
    /// Default while other categories exist does not resurrect it.
    func ensuringDefault(_ current: [EntryCategory]) -> [EntryCategory]?

    /// Builds a new category appended after the existing ones (sortIndex = max + 1),
    /// trimming the name for storage. Non-empty validation is the Request's job (run
    /// by the validation decorator), mirroring `SavedEntryService.registering` — the
    /// transform trusts validated input and does not guard.
    func registering(_ current: [EntryCategory], name: String)
        -> (categories: [EntryCategory], registered: EntryCategory)

    /// Renumbers categories 0..n in `orderedIDs` order, appending any unmentioned
    /// categories at the end in their current order. Returns `nil` (no-op) when
    /// fewer than two of the given ids match existing categories.
    func reordering(_ current: [EntryCategory], orderedIDs: [UUID]) -> [EntryCategory]?

    /// Applies a name + menu-bar-visibility edit to the category with `id`,
    /// preserving its id and sortIndex, trimming the name for storage. Returns the
    /// full collection for the UseCase to commit via `tx.replaceAll`. Throws
    /// `.itemNotFound` when no category matches. Non-empty validation is the
    /// Request's job (run by the validation decorator) — the transform trusts
    /// validated input and does not guard.
    func editing(
        _ current: [EntryCategory],
        id: UUID,
        name: String,
        isHiddenFromMenuBar: Bool
    ) throws -> [EntryCategory]

    /// Removes the category with `id`, returning the remaining categories. Throws
    /// `.itemNotFound` when no category matches — mirrors `SavedEntryService.deleting`
    /// so a stale delete is not silently swallowed.
    func deleting(_ current: [EntryCategory], id: UUID) throws -> [EntryCategory]
}

protocol CommandRunnerServiceProtocol: Sendable {
    /// Hands a `.terminal` command off to the terminal named by `preference`. The caller
    /// (the UseCase) reads the global preference from the owning `TerminalSettingsService`
    /// and passes it in, so this Service does not reach the terminal-settings store itself.
    /// This Service still decides *runnability*: a `.other` (non-scriptable) selection
    /// throws. `.background` commands are not run here — they stream via `stream(_:)`
    /// (`RunStreamingEntryUseCase`); passing one throws.
    /// `currentDirectory` is the resolved global current directory (the UseCase reads it
    /// from `CurrentDirectoryService` and resolves it via `WorkingDirectoryResolver`),
    /// exported into the command's environment as `YOUR_USUAL_CURRENT_DIRECTORY`.
    func perform(_ entry: CommandEntry, preference: TerminalPreference, currentDirectory: URL) async throws

    /// Streams a `.background` command's output incrementally, terminated by an
    /// `.exit` event. Only meaningful for `.background`; a `.terminal` sink yields
    /// nothing and finishes immediately. `currentDirectory` is injected into the
    /// command's environment as `YOUR_USUAL_CURRENT_DIRECTORY`.
    func stream(_ entry: CommandEntry, currentDirectory: URL) -> any AsyncSequence<CommandOutputEvent, Error>
}

/// Owns the global current-directory intent: report the persisted value and replace it.
/// The value is persisted to a state file (shared with the `your-usual cd` CLI) and survives
/// relaunch. Reads return the raw stored path; resolving it to a real directory (with the
/// home fallback) is the UseCase's job via `WorkingDirectoryResolver`, so this Service
/// does not reach the filesystem itself.
protocol CurrentDirectoryServiceProtocol: Sendable {
    /// The current directory preference (raw stored path; resolved to a concrete path by the
    /// store, which self-heals to home when unset).
    func current() -> CurrentDirectoryPreference
    /// Replaces the current directory. `nil`/blank resets to the default (home). Throws on a
    /// genuine write failure — the backing substrate is a file, not process memory.
    func setPath(_ path: String?) throws
}

protocol LaunchAtLoginServiceProtocol: Sendable {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

protocol NotificationServiceProtocol: Sendable {
    /// Delivers a completion notification when the command produced a reportable
    /// result. A `nil` result (e.g. a command handed off to a terminal) is a
    /// no-op — the notification domain owns this "whether to notify" decision.
    func notifyIfNeeded(name: String, result: CommandResult?) async

    /// Delivers a success notification for a run that has no command exit code
    /// (e.g. an AppleScript). Avoids fabricating a `CommandResult` just to reuse
    /// `notifyIfNeeded`.
    func notifyCompletion(name: String) async

    /// Delivers a failure notification when a run could not be performed at all
    /// (e.g. the global terminal is a non-scriptable app). The Domain layer
    /// extracts the user-facing message from the error.
    func notifyFailure(name: String, error: any Error) async
}

protocol RunHistoryServiceProtocol: Sendable {
    func list(forEntry id: UUID) async throws -> [RunRecord]   // newest first
    func listAll() async throws -> [RunRecord]                 // newest first

    /// Builds the run record for a completed background command: stamps the
    /// execution time (injected clock) and wraps the result into the history
    /// outcome. Pure — returns the record for the UseCase to stage via
    /// `tx.registerRun`; this Service does not write it (the transaction boundary
    /// is the UseCase's). Keeps run-record assembly out of the UseCase.
    ///
    /// Named `makeRunRecord` (not a gerund): a gerund (`registering`/`editing`/…) is the
    /// load-bearing signal that the caller must `replaceAll` a whole collection. This
    /// builds a single record the UseCase stages via `tx.registerRun`, so it must NOT
    /// borrow the gerund — that would falsely promise the whole-blob contract.
    func makeRunRecord(
        forEntry entryID: UUID, named entryName: String,
        command: CommandEntry, result: CommandResult
    ) -> RunRecord
}

/// Owns the one-shot legacy `registry.json` → SwiftData import decision, isolated from
/// the everyday entry service so the legacy reader is not a permanent dependency of the
/// other entry use cases. Only `MigrateLegacyRegistryUseCase` (run once at boot) consumes
/// this; once the migration window closes it has no other callers.
protocol LegacyMigrationServiceProtocol: Sendable {
    /// Decides the one-shot legacy import: reads the current registry and, only when
    /// it is empty, reads the legacy `registry.json`. Returns the entries to commit,
    /// or nil (no-op) when the store is already populated or no legacy data exists.
    /// The UseCase commits the returned collection via `tx.replaceAllEntries`.
    func importingLegacy() async throws -> [SavedEntry]?
}

protocol SavedEntryServiceProtocol: Sendable {
    func listAll() async throws -> [SavedEntry]

    /// Decides the one-shot heal of decode-recovered entries: when `current` contains
    /// any recovery placeholder (`isRecovered`), returns the whole collection to persist
    /// — **with the placeholders' `isRecovered` flag cleared** so the write path actually
    /// overwrites the undecodable originals (a flag-set entry would be preserved instead)
    /// — together with `healedCount`, how many placeholders were reset. Returns nil (no-op)
    /// when none are recovered. The UseCase commits `items` via `tx.replaceAllEntries` and
    /// surfaces `healedCount` verbatim: the "which/how many are placeholders" predicate
    /// lives **only** in the Service, never re-evaluated by the UseCase.
    func healingRecovered(_ current: [SavedEntry]) -> (items: [SavedEntry], healedCount: Int)?

    /// Builds a new entry appended after all existing entries (sortIndex = max + 1),
    /// falling back to the Default category when `categoryID` is nil. Returns the
    /// full collection to persist plus the registered entry.
    func registering(_ current: [SavedEntry], name: String, kind: EntryKind, categoryID: UUID?)
        -> (items: [SavedEntry], registered: SavedEntry)

    /// Applies an edit (name / kind / menu-bar visibility, carried by `SavedEntryEdit`)
    /// to the entry with `id`, preserving its id, sortIndex, and categoryID. Returns
    /// the full collection plus the updated entry. Throws `.itemNotFound` when no
    /// entry matches. The fields are bundled into `SavedEntryEdit` so this stays
    /// within the parameter-count limit (a protocol requirement cannot default them).
    func editing(
        _ current: [SavedEntry], id: UUID, edit: SavedEntryEdit
    ) throws -> (items: [SavedEntry], edited: SavedEntry)

    /// Reuses the ascending sortIndex slots the targeted entries occupy to reorder
    /// them per `orderedIDs`, leaving other categories untouched. Returns `nil`
    /// (no-op) when fewer than two given ids match existing entries.
    func reordering(_ current: [SavedEntry], orderedIDs: [UUID]) -> [SavedEntry]?

    /// Moves the entry with `id` to `categoryID`, appending it at the global
    /// max sortIndex + 1. Returns `nil` (no-op) when the entry already belongs to
    /// the target. Throws `.itemNotFound` when no entry matches, or `.categoryNotFound`
    /// when `categoryID` is not in `knownCategoryIDs` (avoids orphaning the entry). The
    /// caller passes the known category ids so this transform stays pure.
    func moving(
        _ current: [SavedEntry], id: UUID, toCategory categoryID: UUID,
        knownCategoryIDs: Set<UUID>
    ) throws -> [SavedEntry]?

    /// Removes the entry with `id`. Throws `.itemNotFound` when no entry matches.
    func deleting(_ current: [SavedEntry], id: UUID) throws -> [SavedEntry]

    /// Replaces only the `currentValue` of the slider entry with `id`, leaving every
    /// other entry — and every non-slider entry sharing that id (none in practice) —
    /// untouched. Returns the whole collection for the UseCase to commit via
    /// `tx.replaceAllEntries`. A gerund (compute-only): persisting the new slider
    /// position is the UseCase's job. Non-throwing: an unknown id or a non-slider match
    /// is a no-op (the slider was deleted/retyped mid-drag), not an error worth
    /// surfacing on a high-frequency commit.
    func editingSliderValue(_ current: [SavedEntry], id: UUID, value: Double) -> [SavedEntry]
}

protocol CommandOutputSettingsServiceProtocol: Sendable {
    /// The current buffer setting (trailing output lines to retain).
    func current() -> CommandOutputPreference
    /// Persists `lines` (clamped to the valid range by `CommandOutputPreference`) and
    /// returns the confirmed preference. **Non-throwing by design** (asymmetric with
    /// `TerminalSettingsService.setPreference`, which throws): the backing store is a
    /// single `UserDefaults` integer write — a property-list primitive that cannot fail —
    /// whereas the terminal preference is JSON encoded to a file, which can. This is *not*
    /// a swallowed error; see `CommandOutputPreferenceStore.saveBufferLines` for the
    /// "make it `throws` if an encoding step is ever added" note.
    func setBufferLines(_ lines: Int) -> CommandOutputPreference
}

protocol TerminalSettingsServiceProtocol: Sendable {
    /// The current terminal preference. Named `current()` to match
    /// `CommandOutputSettingsService.current()` — settings reads share one verb.
    func current() -> TerminalPreference
    /// The known terminals offered in the picker: Terminal.app always, iTerm2 only
    /// when installed. Other apps are added at selection time via `resolveApp`.
    func availableTerminals() -> [TerminalAppSelection]
    /// Assembles the `TerminalPreference` from the chosen app and mode — clamping the
    /// mode to one the app supports (the (app, mode) validity rule lives in
    /// `TerminalPreference`) — persists it, and returns the confirmed preference.
    func setPreference(selection: TerminalAppSelection, launchMode: TerminalLaunchMode) throws
        -> TerminalPreference
    /// Resolves a browsed `.app` URL and classifies it: `.known` when its bundle id
    /// matches a `TerminalApp` we can drive natively, otherwise `.other`. Nil if the
    /// URL is not an app.
    func resolveApp(at url: URL) -> TerminalAppSelection?
    /// One-shot startup hygiene: rewrite the stored preference to its canonical form so it
    /// stops re-warning on every read — resetting an undecodable blob to default, or
    /// canonicalizing a coerced `launchMode` (selection kept). Returns whether a write
    /// occurred.
    func normalizeStoredPreference() throws -> Bool
}

protocol WorkingDirectoryResolverProtocol: Sendable {
    /// Resolves a user-supplied working-directory path to a valid directory URL,
    /// falling back to the home directory when the input is empty or not a
    /// real directory.
    func resolve(_ path: String?) -> URL
}

protocol InstalledAppServiceProtocol: Sendable {
    /// Resolves a picked `.app` URL to its raw installed-app identity (bundle id +
    /// name), or nil if the URL is not a readable app. No classification — unlike
    /// `TerminalSettingsService.resolveApp`, the file/browse form only needs the
    /// identity of whatever app the user chose to open a path with.
    func resolveApp(at url: URL) -> BrowsedApp?
}

protocol AppIconServiceProtocol: Sendable {
    /// Resolves an installed app's icon to a cached PNG file URL, or nil when the
    /// bundle id resolves to no installed app. Backed by the filesystem image cache.
    func resolveIconFile(forBundleIdentifier bundleIdentifier: String) async throws -> URL?
}

/// Provides reads and pure factory/transform helpers for the Pad feature.
/// Writes are staged by the UseCase via `tx.*` operations.
protocol PadServiceProtocol: Sendable {

    // MARK: - Reads (delegate to repositories)

    func listAll() async throws -> [PadLayout]
    func list(forLayout layoutID: UUID) async throws -> [PadCell]
    func listAllCells() async throws -> [PadCell]

    // MARK: - Pure factories (no side effects; UseCase stages result via tx)

    /// Creates a new PadLayout value. `sortIndex` is caller-supplied (UseCase reads
    /// current layouts to compute max+1 before calling).
    func makePadLayout(name: String, columns: Int, rows: Int, sortIndex: Int) -> PadLayout

    /// Returns a copy of `layout` with updated fields.
    func updatingPadLayout(_ layout: PadLayout, name: String, columns: Int, rows: Int) -> PadLayout

    /// Reorders `current` to match `orderedIDs`, renumbering `sortIndex` 0..n. Layouts
    /// not mentioned in `orderedIDs` keep their relative order at the end. Returns `nil`
    /// when there is nothing to reorder (fewer than two recognized ids). Mirrors
    /// `CategoryServiceProtocol.reordering`; the UseCase stages the result per-record.
    func reordering(_ current: [PadLayout], orderedIDs: [UUID]) -> [PadLayout]?

    /// Validates that the cell fits in `layout` and creates a `PadCell` value from
    /// `draft` (assigning a fresh id + `layoutID`). Throws `OperationError.invalidItem`
    /// when the span overflows the grid.
    ///
    /// `linkedEntryKind` is the kind of the entry the cell links to (`nil` = no linked
    /// entry, treated as a button). It is supplied by the UseCase — a cross-concern fact
    /// resolved from the entry registry, mirroring `moving`'s `knownCategoryIDs` — so this
    /// Service can enforce the slider geometry rules (`rowSpan == 1`, `columnSpan >= 2`,
    /// no icon/label) without reaching the entry store itself.
    func makePadCell(
        layoutID: UUID,
        draft: PadCellDraft,
        fitting layout: PadLayout,
        linkedEntryKind: EntryKind?
    ) throws -> PadCell

    /// Removes cells that no longer fit after a grid resize.
    func prunedCells(_ cells: [PadCell], forNewColumns columns: Int, newRows rows: Int) -> [PadCell]

    /// Upserts `newCell` into `cells` (replaces the existing cell at the same origin,
    /// then appends). Throws `OperationError.invalidItem` when `newCell`'s span would
    /// overlap any *other* cell (the same-origin cell being replaced is excluded).
    func applyingCellChange(_ cells: [PadCell], newCell: PadCell) throws -> [PadCell]

    /// Removes the cell at origin (column, row) from `cells`. No-op when absent.
    func removingCell(at column: Int, row: Int, from cells: [PadCell]) -> [PadCell]

    // MARK: - Icon image (filesystem substrate; outside `transaction`)

    /// The directory where pad-icon PNGs are stored. The UseCase joins it with a
    /// filename to form an absolute URL when reading.
    func iconsDirectory() async throws -> URL

    /// Lightly probes a source image's pixel dimensions (without fully decoding it).
    /// Used to lay out the crop UI.
    func probeIconSize(source: URL) async throws -> PixelSize

    /// Crops `source` to `crop`, downscales to 512², and saves it as a PNG. Returns
    /// the generated filename.
    func importIcon(source: URL, crop: IconCrop) async throws -> String

    /// Deletes an icon PNG (best-effort; a missing file is not an error).
    func deleteIcon(name: String) async throws
}
