import Foundation

extension EntryKindPayload {
    /// Supplementary label for the menu / settings list (kind + launch method).
    var displayLabel: String {
        switch self {
        case .browse(let browse):
            switch browse.app {
            case .default:
                return "Default app"
            case .app(let bundleIdentifier):
                return "Open with \(bundleIdentifier)"
            }
        case .command(let command):
            switch command.sink {
            case .background:
                return "Run in background"
            case .terminal:
                return "Run in terminal"
            }
        case .appleScript:
            return "Run AppleScript"
        case .slider:
            return "Adjust value"
        }
    }

    /// True only for a command configured to run in the background (its result is
    /// delivered as a notification rather than by opening a window/terminal).
    /// Presentation mutes this entry's list icon to signal its quieter, non-interactive nature.
    var isBackgroundCommand: Bool {
        if case .command(let command) = self { return command.sink == .background }
        return false
    }

    /// Bundle id of the app a File/Directory entry opens with, when a specific app is
    /// chosen (not the system default). nil for every other kind and for `.default`.
    /// Drives the Settings list's app-icon lookup.
    var appBundleIdentifier: String? {
        if case .browse(let browse) = self, case .app(let bundleIdentifier) = browse.app {
            return bundleIdentifier
        }
        return nil
    }

    /// True only for a command configured to run in a terminal (interactive — it opens
    /// a terminal window/tab). The menu bar tints its icon with the key colour to set it
    /// apart from the muted background commands and the fire-and-forget browse/folder rows.
    var isTerminalCommand: Bool {
        if case .command(let command) = self { return command.sink == .terminal }
        return false
    }

    /// SF Symbol shown beside the entry in the menu.
    var iconSystemName: String {
        switch self {
        case .browse:      return "folder"
        case .command:     return "terminal"
        case .appleScript: return "applescript"
        case .slider:      return "slider.horizontal.3"
        }
    }
}
