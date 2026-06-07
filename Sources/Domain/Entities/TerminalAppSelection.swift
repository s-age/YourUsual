import Foundation

/// The terminal application a command should run in, for the global setting.
///
/// Reuses `TerminalApp` for the two terminals we can drive natively, and adds an
/// `.other` case for any user-browsed `.app` we can only launch (no tab/window
/// scripting). This global selection is what `CommandSink.terminal` runs in.
enum TerminalAppSelection: Equatable, Sendable {
    case known(TerminalApp)                              // Terminal.app or iTerm2
    case other(bundleIdentifier: String, name: String)  // any other browsed app

    var bundleIdentifier: String {
        switch self {
        case .known(let app):      return app.bundleIdentifier
        case .other(let id, _):    return id
        }
    }

    /// The launch modes this terminal can actually drive. Business rule:
    /// - iTerm2 → all three (rich AppleScript: create window/tab, reuse by id)
    /// - Terminal.app → window + reuse only (no AppleScript-native "new tab")
    /// - any other app → launch only (we can't script it), modelled as `.newWindow`
    var supportedModes: [TerminalLaunchMode] {
        switch self {
        case .known(.iterm):    return [.newWindow, .newTab, .reuse]
        case .known(.terminal): return [.newWindow, .reuse]
        case .other:            return [.newWindow]
        }
    }
}
