import AppKit
import Foundation

/// Runs a command in a chosen terminal (Terminal.app / iTerm2) via `NSAppleScript`,
/// honouring a launch mode: a fresh window, a fresh tab, or reusing a window kept
/// across runs. `NSAppleScript` is executed on the main thread, as required by the
/// scripting bridge.
///
/// For `reuse`, the script returns the window id it used; that id is persisted per
/// terminal (in `UserDefaults`) and fed back on the next run, where the script
/// checks `exists window id N` and falls back to a new window if it was closed.
///
/// Tradeoff: the `NSAppleScript` run is synchronous on the main thread (the
/// scripting bridge mandates it), so launching/activating a terminal blocks the
/// UI for its duration. Acceptable because `do script` / `write text` return
/// quickly once the app is up; the `reuse` path needs the returned window id, so
/// it cannot trivially move off-main via `osascript`.
final class TerminalLauncher: TerminalLauncherProtocol, Sendable {
    private let reuseWindowStore: any ReuseWindowStoreProtocol

    init(reuseWindowStore: any ReuseWindowStoreProtocol) {
        self.reuseWindowStore = reuseWindowStore
    }

    func run(commandLine: String, directories: CommandDirectoriesDTO,
             inTerminalBundleIdentifier bundleIdentifier: String,
             launchMode: String) async throws {
        let fullLine = Self.fullCommandLine(commandLine: commandLine,
                                            workingDirectory: directories.workingDirectory,
                                            currentDirectory: directories.currentDirectory)
        let mode = LaunchMode(rawValue: launchMode) ?? .newWindow
        let savedID = mode == .reuse
            ? reuseWindowStore.reuseWindowID(forTerminal: bundleIdentifier)
            : nil
        let source = try Self.appleScriptSource(commandLine: fullLine,
                                                bundleIdentifier: bundleIdentifier,
                                                mode: mode,
                                                savedWindowID: savedID)

        let returnedID = try await MainActor.run { () -> String? in
            guard let script = NSAppleScript(source: source) else {
                throw OperationError.terminalLaunchFailed(reason: "Could not compile AppleScript")
            }
            var errorInfo: NSDictionary?
            let result = script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String
                    ?? "Unknown AppleScript error"
                throw OperationError.terminalLaunchFailed(reason: message)
            }
            return result.stringValue
        }

        if mode == .reuse, let returnedID, !returnedID.isEmpty {
            reuseWindowStore.setReuseWindowID(returnedID, forTerminal: bundleIdentifier)
        }
    }

    /// Mirror of `TerminalLaunchMode` (Domain) — Infrastructure cannot import it,
    /// so the raw value crosses the boundary as a string.
    private enum LaunchMode: String {
        case newWindow, newTab, reuse
    }

    // MARK: - Command line composition

    /// Composes the line handed to the terminal: first export the global current
    /// directory as `YOUR_USUAL_CURRENT_DIRECTORY` (kept for backward-compat with commands
    /// that reference it, e.g. `cd "${YOUR_USUAL_CURRENT_DIRECTORY}"`), then `cd` into the
    /// effective directory — the entry's working directory when set, otherwise the global
    /// current directory — then the user's command verbatim. The command line is passed
    /// through unquoted (the terminal is itself a shell, so redirection/pipes/globs apply);
    /// only the app-supplied path values are single-quoted.
    private static func fullCommandLine(commandLine: String,
                                        workingDirectory: URL?,
                                        currentDirectory: URL) -> String {
        let export = "export \(CommandEnvironment.currentDirectoryKey)="
            + "\(shellQuote(currentDirectory.path)) && "
        let effective = workingDirectory ?? currentDirectory   // cd into the usual dir by default
        return export + "cd \(shellQuote(effective.path)) && \(commandLine)"
    }

    /// Single-quotes a path value, escaping embedded single quotes via `'\''`.
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes a string for use inside an AppleScript double-quoted literal.
    ///
    /// A raw newline inside a `"..."` literal makes the AppleScript fail to compile,
    /// so multi-line registered commands would silently break. We can't keep them as
    /// literal newlines, so each CR/LF is spliced out of the quoted literal and
    /// concatenated back in as `linefeed` (ASCII 10) — the character the shell on the
    /// far side of `do script` / `write text` treats as a command newline. CRLF is
    /// collapsed to a single `linefeed` so a Windows-style line ending doesn't inject
    /// a stray carriage return. The result, e.g. `"a" & linefeed & "b"`, compiles and
    /// runs the multi-line command as written.
    private static func appleScriptEscape(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return escaped.replacingOccurrences(of: "\n", with: "\" & linefeed & \"")
    }

    // MARK: - AppleScript dialects

    private static func appleScriptSource(commandLine: String,
                                          bundleIdentifier: String,
                                          mode: LaunchMode,
                                          savedWindowID: String?) throws -> String {
        let escaped = appleScriptEscape(commandLine)
        switch bundleIdentifier {
        case "com.apple.Terminal":
            return terminalAppSource(command: escaped, mode: mode, savedWindowID: savedWindowID)
        case "com.googlecode.iterm2":
            return itermSource(command: escaped, mode: mode, savedWindowID: savedWindowID)
        default:
            throw OperationError.terminalLaunchFailed(
                reason: "Unsupported terminal: \(bundleIdentifier)")
        }
    }

    /// Terminal.app has no AppleScript-native "new tab", so `newTab` falls back to
    /// a new window (the global setting never offers `newTab` for Terminal.app).
    private static func terminalAppSource(command: String, mode: LaunchMode,
                                          savedWindowID: String?) -> String {
        switch mode {
        case .newWindow, .newTab:
            return """
            tell application "Terminal"
                activate
                do script "\(command)"
            end tell
            """
        case .reuse where savedWindowID != nil:
            return """
            tell application "Terminal"
                activate
                if (exists window id \(savedWindowID!)) then
                    do script "\(command)" in selected tab of window id \(savedWindowID!)
                    set frontmost of window id \(savedWindowID!) to true
                    return "\(savedWindowID!)"
                else
                    do script "\(command)"
                    return (id of front window) as text
                end if
            end tell
            """
        case .reuse:
            return """
            tell application "Terminal"
                activate
                do script "\(command)"
                return (id of front window) as text
            end tell
            """
        }
    }

    private static func itermSource(command: String, mode: LaunchMode,
                                    savedWindowID: String?) -> String {
        switch mode {
        case .newWindow:
            return """
            tell application "iTerm"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow to write text "\(command)"
            end tell
            """
        case .newTab:
            return """
            tell application "iTerm"
                activate
                if (count of windows) = 0 then
                    create window with default profile
                else
                    tell current window to create tab with default profile
                end if
                tell current session of current window to write text "\(command)"
            end tell
            """
        case .reuse where savedWindowID != nil:
            return """
            tell application "iTerm"
                activate
                if (exists window id \(savedWindowID!)) then
                    tell current session of window id \(savedWindowID!) to write text "\(command)"
                    select window id \(savedWindowID!)
                    return "\(savedWindowID!)"
                else
                    set newWindow to (create window with default profile)
                    tell current session of newWindow to write text "\(command)"
                    return (id of newWindow) as text
                end if
            end tell
            """
        case .reuse:
            return """
            tell application "iTerm"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow to write text "\(command)"
                return (id of newWindow) as text
            end tell
            """
        }
    }
}
