import SwiftUI

/// SwiftUI app definition. Hosts the menu-bar menu and the settings window, both
/// driven by ViewModels produced by the root `Container`'s Presentation layer.
/// AppKit is confined to this layer (`NSApplicationDelegateAdaptor` +
/// `AppBootstrap`); everything below is pure protocol-wired layers.
///
/// Not `@main`: the executable's entry point is `main.swift`, which first routes the
/// `your-usual cd <path>` CLI subcommand (forwarding it to the running instance via the
/// URL scheme) before booting this GUI via `YourUsualApp.main()`.
struct YourUsualApp: App {
    @NSApplicationDelegateAdaptor(AppBootstrap.self) private var bootstrap

    var body: some Scene {
        let container = bootstrap.container
        // One shared instance drives the menu, the result window, and the label's
        // result-window trigger (it is cached in PresentationContainer, but bind it once
        // here so all three demonstrably observe the same VM).
        let menuItemsViewModel = container.presentation.makeMenuItemsViewModel()

        MenuBarExtra {
            MenuBarRootView(
                viewModel: menuItemsViewModel,
                padViewModel: container.presentation.makePadViewModel(),     // shared instance
                activate: { NSApplication.shared.activate(ignoringOtherApps: true) },
                openPad: { id in bootstrap.togglePad(id: id) },
                revealCurrentDirectorySettings: {
                    container.presentation.makeSettingsViewModel().revealCurrentDirectory()
                },
                quit: { NSApplication.shared.terminate(nil) }
            )
        } label: {
            // The status-item label is the only always-mounted view, so it owns the
            // result-window trigger: it surfaces the Result window whenever a background run
            // reports output, even if the menu was dismissed after launch. `activate` is
            // required because an `.accessory` app's window would otherwise open behind the
            // frontmost app with no Dock/switcher entry to surface it.
            MenuBarBowtieLabel(
                viewModel: menuItemsViewModel,
                activate: { NSApplication.shared.activate(ignoringOtherApps: true) }
            )
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsRootView(
                viewModel: container.presentation.makeSettingsViewModel(),
                padViewModel: container.presentation.makePadViewModel(),
                terminalViewModel: container.presentation.makeTerminalSettingsViewModel(),
                commandOutputViewModel: container.presentation.makeCommandOutputSettingsViewModel(),
                currentDirectoryViewModel: container.presentation.makeCurrentDirectorySettingsViewModel(),
                makeFormViewModel: { container.presentation.makeFormViewModel(editing: $0, categoryID: $1) },
                makeHistoryViewModel: { container.presentation.makeHistoryViewModel(entry: $0) }
            )
        }
        .defaultSize(width: 480, height: 360)
        .windowResizability(.contentMinSize)
        // Windows only ever open explicitly from the menu (`openWindow`). Disable macOS scene
        // restoration so a cold launch — e.g. `your-usual cd <path>` waking the app via `open`
        // — does NOT auto-reopen a Settings window that was left open at last quit.
        .restorationBehavior(.disabled)
        // `restorationBehavior` only suppresses *restored* windows; SwiftUI still auto-presents
        // the first `Window` scene at a cold launch. When `your-usual cd` wakes a not-running app
        // via `open`, that surfaced the Settings window. `.suppressed` makes the scene open only
        // on an explicit `openWindow`, never at launch.
        .defaultLaunchBehavior(.suppressed)

        // Standalone window for a background command's run output. Shares the
        // menu's `MenuItemsViewModel` instance, so it streams live; styled
        // headerless so it reads as a lightweight result viewer.
        Window("Result", id: "result") {
            CommandResultView(viewModel: menuItemsViewModel)
        }
        .defaultSize(width: 560, height: 380)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        // Same as Settings: open only via explicit `openWindow`, never auto-present at launch.
        .defaultLaunchBehavior(.suppressed)

        // Each Launcher Pad is hosted in its own non-activating AppKit NSPanel (see
        // PadWindowManager) rather than a SwiftUI Window scene, so tapping a cell
        // fires its action without stealing focus from the foreground app — the
        // capability a SwiftUI `Window` cannot express. Pads are summoned by id from
        // the menu bar's "Pads" section via `bootstrap.togglePad(id:)`.
    }
}
