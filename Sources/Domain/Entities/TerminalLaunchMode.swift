import Foundation

/// How a command is delivered to the chosen terminal.
///
/// Which of these a given terminal can actually drive is decided by
/// `TerminalAppSelection.supportedModes` — not every terminal supports every mode.
enum TerminalLaunchMode: String, CaseIterable, Equatable, Sendable {
    case newWindow   // always open a fresh window
    case newTab      // always open a fresh tab in the current window
    case reuse       // first run opens a tab, later runs reuse it

    static let `default` = TerminalLaunchMode.newWindow
}
