import Foundation

/// A persisted command run: the executed command line plus its `CommandResult`.
///
/// Composes `CommandResult` rather than re-declaring its fields, so exit code,
/// output, and `succeeded` have a single source of truth.
struct CommandRunOutcome: Equatable, Sendable {
    let commandLine: String   // snapshot of the executed command line
    let result: CommandResult

    var exitCode: Int32 { result.exitCode }
    var stdout: String { result.stdout }
    var stderr: String { result.stderr }
    var succeeded: Bool { result.succeeded }

    init(commandLine: String, result: CommandResult) {
        self.commandLine = commandLine
        self.result = result
    }
}
