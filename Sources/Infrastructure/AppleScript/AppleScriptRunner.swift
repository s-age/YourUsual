import AppKit
import Foundation

/// Compiles and executes an AppleScript source string on the main thread,
/// as required by `NSAppleScript`. Returns the script's string result (the
/// descriptor's `stringValue`), or nil when the script produces no string.
///
/// Tradeoff: `executeAndReturnError` is synchronous and `NSAppleScript`
/// mandates the main thread, so a slow script blocks the UI for its full
/// duration. Scripts here are expected to be short; a long-running one would
/// beachball the menu bar. If that becomes a problem, move to `osascript` via
/// `Process` (off-main) for sources whose string result is unused.
final class AppleScriptRunner: AppleScriptRunnerProtocol, Sendable {
    func run(source: String) async throws -> String? {
        try await MainActor.run {
            guard let script = NSAppleScript(source: source) else {
                throw OperationError.applescriptFailed(reason: "Could not compile AppleScript")
            }
            var errorInfo: NSDictionary?
            let descriptor = script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String
                    ?? "Unknown AppleScript error"
                throw OperationError.applescriptFailed(reason: message)
            }
            return descriptor.stringValue
        }
    }
}
