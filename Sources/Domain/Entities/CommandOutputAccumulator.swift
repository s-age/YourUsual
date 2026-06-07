import Foundation

/// Folds a `CommandOutputEvent` stream into a bounded `CommandResult`. It routes each
/// event into the matching stdout/stderr scroll buffer and, on the terminal exit code,
/// assembles the result. Deciding *how much* of a run's output to keep, and *how* the
/// event stream becomes a stored/notified result, is a domain decision — so the fold
/// lives here, and the streaming use case only drives iteration and wiring (transport,
/// notification, persistence), holding no output logic of its own.
struct CommandOutputAccumulator: Sendable {
    private var stdout: BoundedLineBuffer
    private var stderr: BoundedLineBuffer

    init(maxLines: Int) {
        stdout = BoundedLineBuffer(maxLines: maxLines)
        stderr = BoundedLineBuffer(maxLines: maxLines)
    }

    /// Accumulates one streamed event. `.exit` carries no body — it terminates the run;
    /// call `result(exitCode:)` to build the final record from the accumulated output.
    mutating func ingest(_ event: CommandOutputEvent) {
        switch event {
        case .stdout(let text): stdout.append(text)
        case .stderr(let text): stderr.append(text)
        case .exit: break
        }
    }

    func result(exitCode: Int32) -> CommandResult {
        CommandResult(exitCode: exitCode, stdout: stdout.text, stderr: stderr.text)
    }
}
