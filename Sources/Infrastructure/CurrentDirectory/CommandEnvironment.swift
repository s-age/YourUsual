import Foundation

/// Shared vocabulary for the environment a registered command is run with. The
/// global current-directory value is injected under this key into every command
/// execution (both the background `ProcessRunner` and the terminal `TerminalLauncher`),
/// so a command can reference `$YOUR_USUAL_CURRENT_DIRECTORY` regardless of which
/// terminal session/tab it runs in — the value comes from the app, not the shell.
/// Kept in one place so the two injection sites cannot drift on the magic key string.
enum CommandEnvironment {
    static let currentDirectoryKey = "YOUR_USUAL_CURRENT_DIRECTORY"
}
