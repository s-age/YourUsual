import Foundation
import Observation

/// One menu section: a category header followed by the entries it owns.
struct MenuCategorySection: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let items: [SavedEntryResponse]
}

/// Accumulated output of a background command's latest run this session, shown in
/// the per-entry hover mini-window.
struct CommandOutput: Equatable, Sendable {
    /// Run lifecycle. Modeled as one enum so "running" and "finished (code, succeeded)"
    /// are the only representable states — an exit code can never exist without its
    /// success flag (or vice versa), unlike two independent Optionals.
    enum Completion: Equatable, Sendable {
        case running
        case finished(code: Int32, succeeded: Bool)
    }

    var stdout: String = ""
    var stderr: String = ""
    var completion: Completion = .running

    var isFinished: Bool {
        if case .finished = completion { return true }
        return false
    }

    /// Per-buffer size budget for the live output window, measured in UTF-8 **bytes**
    /// (`String.utf8.count`), not graphemes or UTF-16 units. ~200k bytes keeps a long
    /// build/test log's recent tail visible (tens of thousands of lines) while bounding
    /// memory and per-append cost: after a trim the buffer is brought back near this
    /// budget, so a chatty command can't grow it unboundedly or jank the main actor.
    /// Bytes are used because `String.utf8.count` is the string's stored byte count —
    /// an O(1) read on a native Swift string regardless of content, which `utf16.count`
    /// is **not** (it is an O(buffer) scan once any non-ASCII is present). The cap only
    /// needs to bound size, not count graphemes exactly, so bytes are the honest unit.
    /// The persisted RunHistory (capped separately at 200 rows) is the durable record;
    /// this is just the in-session live view.
    static let maxOutputBytes = 200_000

    /// Slack above `maxOutputBytes` the buffer may grow to before a trim is triggered
    /// (the high-water mark = cap + slack). A trim over-shoots down to ~`maxOutputBytes`
    /// (the low-water mark), so a trim only happens once every ~`slack` appended bytes
    /// rather than on every append once the buffer is near the cap — amortizing the
    /// O(buffer) trim scan. The common append path is an O(1) `utf8.count` compare
    /// against the high-water mark and returns.
    static let outputSlackBytes = 50_000

    private static let truncationMarker = "…(earlier output truncated)…\n"

    /// Appends `text` to `buffer`. The common path is a concatenation plus an O(1)
    /// `utf8.count` compare against the high-water mark (`cap + slack`) — no O(buffer)
    /// scan, so a chatty command (including non-ASCII output: emoji, box-drawing) can't
    /// turn each append into an O(buffer) length check on the MainActor.
    ///
    /// Only once the buffer exceeds the high-water mark do we trim: keep the most recent
    /// tail within the low-water **byte** budget, walking whole Characters from the end
    /// so a grapheme (and its UTF-8/UTF-16 bytes) is never split, then prepend the
    /// truncation marker. Byte-bounding the tail — not a Character count — is what makes
    /// the trimmed buffer actually drop below the budget for multibyte output; a
    /// Character-count bound could keep far more bytes and re-trigger a trim on every
    /// append. Because we over-trim to the low-water mark, trims are rare (amortized one
    /// per ~`outputSlackBytes` appended bytes) and the marker never accumulates.
    static func append(_ text: String, to buffer: inout String) {
        buffer += text
        // O(1) on a native Swift string (stored byte count); skip the trim path until
        // we cross the high-water mark.
        guard buffer.utf8.count > maxOutputBytes + outputSlackBytes else { return }
        // Reserve room for the marker so marker + tail together fit the byte budget.
        let budget = max(0, maxOutputBytes - truncationMarker.utf8.count)
        var start = buffer.endIndex
        var bytes = 0
        while start > buffer.startIndex {
            let prev = buffer.index(before: start)
            let charBytes = buffer[prev].utf8.count
            if bytes + charBytes > budget { break }
            bytes += charBytes
            start = prev
        }
        buffer = truncationMarker + String(buffer[start...])
    }
}

@Observable
@MainActor
final class MenuItemsViewModel {
    private(set) var launchAtLogin = false

    /// User-facing message for the most recent failed open/load, surfaced as an
    /// alert. Set instead of swallowing the error so a click on a missing
    /// path/app — or a read failure — is visible rather than failing silently.
    var actionError: String?

    /// Latest run output per background entry, session-scoped (in-memory).
    private(set) var outputs: [UUID: CommandOutput] = [:]
    /// Entry whose run the standalone result window should display. The window
    /// observes this (and `outputs`) so it tracks the latest run; `nil` shows the
    /// window's empty state. Set only when a run is actually presented (first output,
    /// or a failure) — a silent exit-0 run never retargets the window.
    private(set) var resultWindowEntryID: UUID?
    /// Monotonic counter bumped whenever a run wants the result window brought forward —
    /// the first time it produces output, or when it finishes with a non-zero exit even
    /// without output. The **always-mounted status-item label** observes this via `.onChange`
    /// and performs the `activate()` + `openWindow` (Presentation may not touch AppKit, so the
    /// actual window-open lives in the App-layer label View). It must be the label, not the
    /// menu popover content (`MenuBarRootView`), because that content unmounts when the menu
    /// closes and would miss a tick raised by output arriving after the menu was dismissed.
    /// A run that finishes exit 0 with no output never bumps it, so no window appears — the
    /// completion notification is its only surface.
    private(set) var presentResultTick: Int = 0
    /// Live consumer tasks, kept off the view so a run survives the menu closing.
    /// Single source of truth for "is this command running" — an id is running
    /// iff it has a live task here (see `isRunning(_:)`).
    private var runTasks: [UUID: Task<Void, Never>] = [:]
    /// Per-id generation counter, bumped on every `run`/`deleteResult`. A run's
    /// stored task clears its `runTasks[id]` slot in `defer` only while it still
    /// owns the current generation. Without this, a cancelled run resuming late
    /// (its stream cancel is not instantaneous) would clear the slot of a *newer*
    /// run that already replaced it — the delete-then-immediately-rerun race — so
    /// `isRunning` would lie and a third run could open a second stream onto the
    /// same id.
    private var runEpoch: [UUID: Int] = [:]

    /// The global current directory shown after "Settings" in the menu. Resolved
    /// (always a valid absolute path; home when unset). Refreshed on `load()`; the value is
    /// persisted (set via the `your-usual cd` CLI or the Settings pane), so each open re-reads it.
    private(set) var currentDirectory: CurrentDirectoryResponse?

    private let registry: RegistryViewModel
    private let openEntry: OpenEntryUseCaseProtocol
    private let runStreamingEntry: RunStreamingEntryUseCaseProtocol
    private let deleteHistory: DeleteHistoryUseCaseProtocol
    private let readLaunchAtLogin: ReadLaunchAtLoginUseCaseProtocol
    private let setLaunchAtLoginUseCase: SetLaunchAtLoginUseCaseProtocol
    private let readCurrentDirectory: ReadCurrentDirectoryUseCaseProtocol
    /// Shared with settings so an icon resolved on either surface is reused.
    private let appIcons: AppIconCache

    /// Read-only pass-throughs to the shared registry; the menu observes it via
    /// `@Observable`, so cross-scene changes propagate without a revision counter.
    var items: [SavedEntryResponse] { registry.items }
    var categories: [CategoryResponse] { registry.categories }

    /// Entries grouped under their category, ordered by category sort index, with
    /// menu-bar-hidden items removed. Drops, in order: (a) hidden categories, (b) hidden
    /// entries, and (c) entries owned by a hidden category — (c) is required because an
    /// entry whose category is filtered out would otherwise fold into the fallback
    /// section (`group`'s orphan rule) and re-surface. The standalone Pad and Settings
    /// read the registry directly, so they are unaffected by this menu-only filter.
    var sections: [MenuCategorySection] {
        let hiddenCategoryIDs = Set(categories.filter(\.isHiddenFromMenuBar).map(\.id))
        let visibleCategories = categories.filter { !$0.isHiddenFromMenuBar }
        let visibleItems = items.filter {
            !$0.isHiddenFromMenuBar && !hiddenCategoryIDs.contains($0.categoryID)
        }
        return Self.group(items: visibleItems, categories: visibleCategories)
    }

    init(
        registry: RegistryViewModel,
        openEntry: OpenEntryUseCaseProtocol,
        runStreamingEntry: RunStreamingEntryUseCaseProtocol,
        deleteHistory: DeleteHistoryUseCaseProtocol,
        readLaunchAtLogin: ReadLaunchAtLoginUseCaseProtocol,
        setLaunchAtLogin: SetLaunchAtLoginUseCaseProtocol,
        readCurrentDirectory: ReadCurrentDirectoryUseCaseProtocol,
        appIcons: AppIconCache
    ) {
        self.registry = registry
        self.openEntry = openEntry
        self.runStreamingEntry = runStreamingEntry
        self.deleteHistory = deleteHistory
        self.readLaunchAtLogin = readLaunchAtLogin
        self.setLaunchAtLoginUseCase = setLaunchAtLogin
        self.readCurrentDirectory = readCurrentDirectory
        self.appIcons = appIcons
    }

    func load() async {
        do {
            try await registry.load()
        } catch is CancellationError {
            // `.task`-driven: the menu window opening/closing cancels this load.
            // Cancellation is normal control flow, not a user-facing failure — do
            // not surface it as an alert.
            return
        } catch {
            // Registry load is the primary failure here — surface it and stop, so a
            // secondary launch-read failure below can't overwrite the more important
            // (menu-content) error with its own message.
            actionError = error.localizedDescription
            return
        }
        // Surface a read failure rather than silently showing OFF — symmetric with
        // the write path (`setLaunchAtLogin`). On failure keep the prior value so the
        // switch never lies about a state we merely failed to read.
        do {
            launchAtLogin = try readLaunchAtLogin.execute(ReadLaunchAtLoginRequest())
        } catch {
            actionError = error.localizedDescription
        }
        // Best-effort: the current-directory display is non-critical, so a read failure
        // keeps the prior value rather than overwriting the (more important) content error.
        currentDirectory = (try? readCurrentDirectory.execute(ReadCurrentDirectoryRequest())) ?? currentDirectory
        await appIcons.resolve(for: items)
    }

    private static func group(
        items: [SavedEntryResponse],
        categories: [CategoryResponse]
    ) -> [MenuCategorySection] {
        let ordered = categories.sorted { $0.sortIndex < $1.sortIndex }
        // Categories not loaded yet: keep entries visible under a single Default
        // header rather than hiding them until the next reload.
        guard let fallback = ordered.first?.id else {
            guard let anchor = items.first?.categoryID else { return [] }
            return [MenuCategorySection(id: anchor, name: "Default", items: items)]
        }
        let known = Set(ordered.map(\.id))
        var byCategory: [UUID: [SavedEntryResponse]] = [:]
        for item in items {
            let key = item.effectiveCategoryID(known: known, fallback: fallback)
            byCategory[key, default: []].append(item)
        }
        return ordered.map { category in
            MenuCategorySection(id: category.id, name: category.name, items: byCategory[category.id] ?? [])
        }
    }

    func open(_ item: SavedEntryResponse) async {
        // No current-directory refresh here: `open` drives browse (no cd) and terminal-sink
        // commands, which are fire-and-forget — a `your-usual cd` launched in a terminal runs
        // *after* this returns, so a refresh here would read the stale value. The directory is
        // refreshed on the background-run `.exit` path (run(_:)), where completion guarantees
        // the child has written the state file.
        do {
            try await openEntry.execute(OpenEntryRequest(entry: item))
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Background command runs

    func isRunning(_ id: UUID) -> Bool { runTasks[id] != nil }

    func output(for id: UUID) -> CommandOutput? { outputs[id] }

    /// The entry the result window should render, resolved from the registry.
    var resultWindowEntry: SavedEntryResponse? {
        guard let id = resultWindowEntryID else { return nil }
        return items.first { $0.id == id }
    }

    /// Runs a background command, streaming its output into `outputs[id]`. The
    /// run is driven by a stored task so it (and its history persistence) keeps
    /// going even if the menu closes mid-run.
    func run(_ item: SavedEntryResponse) {
        let id = item.id
        guard runTasks[id] == nil else { return }        // no double-runs
        let epoch = (runEpoch[id] ?? 0) + 1              // claim this run's generation
        runEpoch[id] = epoch
        outputs[id] = CommandOutput()                    // clear the prior result

        runTasks[id] = Task { [weak self] in
            guard let self else { return }
            // Clear the slot only if this run still owns it — a late-cancelled
            // earlier run must not wipe a newer run that already replaced it.
            defer { if self.runEpoch[id] == epoch { self.runTasks[id] = nil } }
            // Present the result window lazily: only once this run has something worth
            // showing — output, or a non-zero exit. A silent exit-0 run never opens it.
            var presented = false
            do {
                let stream = try await self.runStreamingEntry.execute(RunStreamingEntryRequest(entry: item))
                for try await chunk in stream {
                    self.apply(chunk, to: id)
                    if !presented, self.shouldPresentResult(id) {
                        presented = true
                        self.requestPresentResult(id)
                    }
                }
                // The command may have been a `your-usual cd <path>` that changed the persisted
                // current directory; by `.exit` the child has written the state file, so refresh
                // now — the menu row binds this @Observable value and updates an open popover live.
                self.refreshCurrentDirectory()
            } catch is CancellationError {
                // Explicit cancellation (e.g. `deleteResult` clearing a live run):
                // exit cleanly. The `defer` still clears `runTasks[id]`; do NOT
                // write a phantom error line into — and thereby re-create —
                // `outputs[id]`, which the user is intentionally discarding.
                return
            } catch {
                // Surface the failure in the mini-window rather than silently dropping it.
                CommandOutput.append(
                    "\n\(error.localizedDescription)",
                    to: &self.outputs[id, default: CommandOutput()].stderr
                )
                self.outputs[id]?.completion = .finished(code: -1, succeeded: false)
                // A stream failure is a failure with output — surface it even if no
                // chunk arrived before the throw (the lazy in-loop present never ran).
                if !presented { self.requestPresentResult(id) }
            }
        }
    }

    /// Deletes the entry's run history and clears its displayed output. If a run
    /// is still live, its task is cancelled first so the stream consumer stops
    /// before we clear local state — otherwise it would re-create `outputs[id]`
    /// (via `apply`) after the delete. The cancelled run exits cleanly (the run
    /// loop's `CancellationError` catch writes no phantom error).
    func deleteResult(_ item: SavedEntryResponse) {
        let id = item.id
        runTasks[id]?.cancel()
        runTasks[id] = nil
        runEpoch[id, default: 0] += 1    // invalidate the cancelled run's defer-clear
        outputs[id] = nil
        if resultWindowEntryID == id { resultWindowEntryID = nil }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.deleteHistory.execute(DeleteHistoryRequest(scope: .entry(id)))
            } catch {
                // Surface the persistent-delete failure rather than dropping it:
                // the local output was cleared optimistically, but if the durable
                // history delete fails the user must see it (consistent with open/load).
                self.actionError = error.localizedDescription
            }
        }
    }

    /// Re-reads the persisted current directory after a background command completes (a
    /// menu-registered `your-usual cd <path>` command). Called only from the `run(_:)` `.exit`
    /// path, where the child has finished writing the state file. Best-effort: a read failure
    /// keeps the prior value rather than blanking the menu row. The row binds this `@Observable`
    /// property, so an already-open popover updates without a reopen.
    private func refreshCurrentDirectory() {
        currentDirectory = (try? readCurrentDirectory.execute(ReadCurrentDirectoryRequest())) ?? currentDirectory
    }

    private func apply(_ chunk: CommandOutputResponse, to id: UUID) {
        switch chunk {
        case .stdout(let text):
            CommandOutput.append(text, to: &outputs[id, default: CommandOutput()].stdout)
        case .stderr(let text):
            CommandOutput.append(text, to: &outputs[id, default: CommandOutput()].stderr)
        case .exit(let code, let succeeded):
            outputs[id, default: CommandOutput()].completion = .finished(code: code, succeeded: succeeded)
        }
    }

    /// Whether this run now warrants bringing the result window forward: it has produced
    /// any output, or it has finished with a non-zero exit (a failure surfaces even with
    /// empty output). A run still running with no output, or one that finished exit 0 with
    /// no output, returns `false` — the latter stays silent, delivered only via the
    /// completion notification (owned in the UseCase), with no window flashed up.
    private func shouldPresentResult(_ id: UUID) -> Bool {
        guard let output = outputs[id] else { return false }
        if !output.stdout.isEmpty || !output.stderr.isEmpty { return true }
        if case .finished(_, let succeeded) = output.completion { return !succeeded }
        return false
    }

    /// Retargets the result window at this run and asks the status-item label to bring it
    /// forward by bumping `presentResultTick`. The actual `activate()` + `openWindow` lives in
    /// the View — Presentation may not touch AppKit, so window presentation is delegated.
    private func requestPresentResult(_ id: UUID) {
        resultWindowEntryID = id
        presentResultTick &+= 1
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        // On success, reflect the state the system actually applied. On failure,
        // surface the error as an alert (consistent with open/load) and fall back
        // to a fresh read so the switch never lies about reality — if that read
        // also fails, keep the prior value.
        do {
            launchAtLogin = try setLaunchAtLoginUseCase.execute(SetLaunchAtLoginRequest(enabled: enabled))
        } catch {
            actionError = error.localizedDescription
            launchAtLogin = (try? readLaunchAtLogin.execute(ReadLaunchAtLoginRequest())) ?? launchAtLogin
        }
    }
}

// MARK: - App icons

extension MenuItemsViewModel {
    /// File URL of the cached icon for the app a browse entry opens with, if resolved;
    /// nil falls back to the SF Symbol. Forwards to the shared `AppIconCache`.
    func appIconURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        appIcons.url(forBundleIdentifier: bundleIdentifier)
    }
}
