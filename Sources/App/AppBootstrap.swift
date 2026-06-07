import AppKit
import UserNotifications

/// `NSApplicationDelegate` for app-lifecycle setup that SwiftUI scenes cannot
/// express: forcing the `.accessory` activation policy (menu-bar-only, no Dock
/// icon) and requesting user-notification authorization on launch.
///
/// Owns the root `Container` so it can trigger the one-shot JSON → SwiftData
/// migration before any registry read occurs.
@MainActor
final class AppBootstrap: NSObject, NSApplicationDelegate {
    let container = Container()

    /// Owns the per-pad non-activating Launcher Pad panels (each built lazily on first
    /// toggle). Held here because the panels must outlive any single SwiftUI `body`.
    /// Every panel binds the *same* shared `PadViewModel` and is pinned to its own pad
    /// via `layoutID`, so opening several pads does not reload or drift state.
    private lazy var padWindows = PadWindowManager { [container] padID in
        PadContainerView(
            viewModel: container.presentation.makePadViewModel(),   // shared instance
            layoutID: padID,
            presentResult: {}   // panel host: don't front the Result window (avoids focus steal)
        )
    }

    /// Show/hide the Launcher Pad panel for `id`. Wired to the menu bar's "Pads" rows.
    func togglePad(id: UUID) { padWindows.toggle(padID: id) }

    /// A menu-bar-only (`.accessory`) app has no primary window, so AppKit's default
    /// "reopen" behaviour must not auto-open one. This fires when the app is activated while
    /// having no visible windows; the default (true) would surface the Settings window.
    /// Windows are only ever opened explicitly from the menu via `openWindow`.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        // Tear down a deleted pad's launcher panel from the App layer (the only layer
        // that may touch `NSPanel`). The shared `PadViewModel` fires `onLayoutDeleted`
        // after a successful delete; close the matching panel so no orphan lingers.
        // Same shared instance the panels bind to (`makePadViewModel()` is memoized).
        //
        // `[weak padWindows]` breaks the otherwise process-lifetime reference cycle
        // (VM → closure → padWindows → makeContent → container → presentation → VM).
        // `self` (AppBootstrap, the app delegate) owns `padWindows` for the whole run,
        // so the weak ref stays alive; this is purely to keep the graph clean.
        container.presentation.makePadViewModel().onLayoutDeleted = { [weak padWindows] id in
            padWindows?.close(padID: id)
        }

        // If the store was unreadable on open, it was backed up aside (never
        // wiped) and an empty one created. Tell the user where their old data went.
        // Otherwise, if an additive-evolved store was lightweight-migrated in place
        // (no data moved), show a one-time, milder "data updated" notice. The two are
        // mutually exclusive, so only one fires.
        if let backupURL = container.storeRecoveryBackupURL {
            presentStoreRecoveryAlert(backupURL: backupURL)
        } else if container.storeWasUpgradedInPlace {
            presentStoreUpgradedNotice()
        }

        // One-shot startup work (JSON → SwiftData migration + Default category
        // seed). Must run regardless of bundle identity so the registry is usable
        // even when launched as a bare SPM executable — otherwise no Default
        // category is seeded and the settings window shows no categories.
        //
        // If a legacy settings file was present but could not be imported, bootstrap
        // returns a warning — surface it so the failed import isn't invisible
        // (symmetric with the store-recovery alert above). It also reports how many
        // stored entries could not be decoded and were reset to a placeholder.
        Task { @MainActor in
            let notice = await container.bootstrap()
            if let warning = notice.migrationWarning {
                presentMigrationFailureAlert(message: warning)
            }
            if notice.resetEntryCount > 0 {
                presentEntriesResetAlert(count: notice.resetEntryCount)
            }
        }

        // `UNUserNotificationCenter.current()` throws an `NSException` (→ `abort`)
        // when invoked outside a code-signed bundle with a valid identifier.
        // Running the bare SPM executable (Xcode scheme, `swift run`, direct
        // `.build` launch) has no bundle identifier, so guard to stay launchable
        // there; notifications work from the installed `.app` bundle.
        guard Bundle.main.bundleIdentifier != nil else { return }

        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Modal alert shown once after the store was recovered: the old data could
    /// not be opened (incompatible/corrupt), so it was moved aside and a fresh
    /// store created. No restart is required — the app is already running on the
    /// new store; this only tells the user where the backup is.
    private func presentStoreRecoveryAlert(backupURL: URL) {
        NSApp.activate(ignoringOtherApps: true)   // .accessory app: surface the alert
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't open your saved data"
        alert.informativeText = """
            Your previous registry could not be opened (an incompatible or corrupt \
            store), so it was moved aside and the app started with empty data. Your \
            old data was preserved here:

            \(backupURL.path)
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Informational notice shown once when the store was migrated in place to the current
    /// schema (an additive change recovered via automatic lightweight migration). Unlike the
    /// recovery alert, no data was moved aside — this is a routine format upgrade, so the
    /// wording is reassuring and mild. Surfaced for observability: a migration that *silently*
    /// changed data would otherwise be invisible (see `RegistryStoreFactory` tier-2 caveat).
    private func presentStoreUpgradedNotice() {
        NSApp.activate(ignoringOtherApps: true)   // .accessory app: surface the notice
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Your saved data was updated"
        alert.informativeText = """
            Your registry was migrated to a newer storage format. All your items were carried \
            over — nothing to do.
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Modal alert shown once when one or more stored items could not be decoded at
    /// launch (e.g. an upgrade dropped a target/handler kind they used) and were reset
    /// to empty File/Directory placeholders. The placeholders are already persisted; the
    /// user just needs to re-enter or delete them.
    private func presentEntriesResetAlert(count: Int) {
        NSApp.activate(ignoringOtherApps: true)   // .accessory app: surface the alert
        let alert = NSAlert()
        alert.alertStyle = .warning
        let noun = count == 1 ? "item" : "items"
        alert.messageText = "Couldn't open \(count) saved \(noun)"
        alert.informativeText = """
            \(count) saved \(noun) could not be opened (an incompatible or corrupt record) \
            and \(count == 1 ? "was" : "were") reset to an empty File / Directory entry, \
            keeping the name. Please re-enter the details, or delete \
            \(count == 1 ? "it" : "them") from Settings.
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Modal alert shown once when a legacy `registry.json` was present at launch
    /// but could not be imported (unreadable or corrupt). The app continues on the
    /// (empty) SwiftData store; the legacy file is left on disk for a future retry.
    private func presentMigrationFailureAlert(message: String) {
        NSApp.activate(ignoringOtherApps: true)   // .accessory app: surface the alert
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't import your previous settings"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
