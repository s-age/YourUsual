import Foundation

/// Runs a registered **run-and-stream** entry, streaming its output to the caller.
/// Two kinds resolve to this style (see `ExecutionStyle.resolve`) and each has its
/// own execution path here — they share only the streaming transport, not the runner:
/// - a **background command** (`backgroundCommandStream`): output is yielded
///   incrementally, and on the terminal `.exit` the prior history is cleared and the new
///   run persisted **atomically** (one transaction) — so a background entry keeps only its
///   latest *completed* run, and a run that fails to spawn leaves the prior record intact.
///   A completion notification is posted on exit.
/// - an **AppleScript** entry (`appleScriptStream`): runs the script and yields its
///   result; no history is kept.
///
/// Open-style kinds (`.terminal` commands, browse) belong to `OpenEntryUseCase` and
/// throw `misroutedEntry` if they reach here.
///
/// The persistence side-effects live in the producer `Task`, so callers must keep
/// consuming the stream to completion (via a stored task, not a view-scoped one)
/// for the run to be recorded even if the menu closes mid-run.
final class RunStreamingEntryUseCase: AsyncUseCase, Sendable {
    /// Upper bound on yielded-but-not-yet-consumed stream events (back-pressure cap; see
    /// `backgroundCommandStream`). Generous slack for normal bursts; only bites if a
    /// runaway command outpaces the `MainActor` consumer.
    private static let maxInFlightEvents = 1024

    private let command: any CommandRunnerServiceProtocol
    private let appleScript: any AppleScriptRunnerServiceProtocol
    private let notification: any NotificationServiceProtocol
    private let history: any RunHistoryServiceProtocol
    private let db: any DBProtocol
    private let diagnostics: any DiagnosticsLoggingProtocol
    private let outputSettings: any CommandOutputSettingsServiceProtocol
    private let currentDirectory: any CurrentDirectoryServiceProtocol
    private let resolver: any WorkingDirectoryResolverProtocol

    init(
        command: any CommandRunnerServiceProtocol,
        appleScript: any AppleScriptRunnerServiceProtocol,
        notification: any NotificationServiceProtocol,
        history: any RunHistoryServiceProtocol,
        db: any DBProtocol,
        diagnostics: any DiagnosticsLoggingProtocol,
        outputSettings: any CommandOutputSettingsServiceProtocol,
        currentDirectory: any CurrentDirectoryServiceProtocol,
        resolver: any WorkingDirectoryResolverProtocol
    ) {
        self.command = command
        self.appleScript = appleScript
        self.notification = notification
        self.history = history
        self.db = db
        self.diagnostics = diagnostics
        self.outputSettings = outputSettings
        self.currentDirectory = currentDirectory
        self.resolver = resolver
    }

    func execute(
        _ request: RunStreamingEntryRequest
    ) async throws -> AsyncThrowingStream<CommandOutputResponse, Error> {
        switch request.entry.kind {
        case .command(let payload) where payload.sink == .background:
            return backgroundCommandStream(payload: payload, entry: request.entry)
        case .appleScript(let payload):
            return appleScriptStream(payload: payload, entryName: request.entry.name)
        case .command, .browse, .slider:
            // `.terminal` commands and browse entries resolve to `.open` (handled by
            // `OpenEntryUseCase`); a slider resolves to `.adjust` (handled by
            // `RunSliderUseCase`). Reaching the run-and-stream path is a routing-invariant
            // violation — fail loudly instead of finishing an empty stream silently, which
            // would read to the user as "ran, produced nothing".
            throw OperationError.misroutedEntry(
                reason: "\(request.entry.name) is not a run-and-stream entry"
            )
        }
    }

    private func backgroundCommandStream(
        payload: CommandPayload,
        entry: SavedEntryResponse
    ) -> AsyncThrowingStream<CommandOutputResponse, Error> {
        // Snapshot the global current directory at launch: resolve it once and substitute
        // the `<WORKING_DIRECTORY>` sentinel (if used) so the run keeps the directory it
        // started with, and inject it as YOUR_USUAL_CURRENT_DIRECTORY for the command.
        let currentDir = resolver.resolve(currentDirectory.current().path)
        let domainCommand = payload.toDomain(resolvingCurrentDirectory: currentDir)
        let entryID = entry.id
        let entryName = entry.name
        let command = self.command
        let notification = self.notification
        let history = self.history
        let db = self.db
        let diagnostics = self.diagnostics
        // Snapshot the buffer setting at launch; the run keeps the value it started with.
        let bufferLines = outputSettings.current().bufferLines

        // Bound the in-flight buffer: the policy caps yielded-but-undrained events, so a
        // runaway command outpacing the MainActor consumer drops the *oldest displayed*
        // events instead of growing memory without bound (the default is `.unbounded`).
        // The authoritative result is bounded and persisted by the producer below
        // (`CommandOutputAccumulator` + history), independently of what the live view
        // drains, so dropping in-flight *display* events loses nothing recorded. `.exit`
        // is the terminal (newest) event, so `.bufferingNewest` always retains it.
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(Self.maxInFlightEvents)) { continuation in
            let producer = Task {
                // The Domain accumulator owns the output fold (stdout/stderr routing +
                // bounded-retention result assembly); this loop is pure transport.
                var output = CommandOutputAccumulator(maxLines: bufferLines)
                do {
                    for try await event in command.stream(domainCommand, currentDirectory: currentDir) {
                        output.ingest(event)
                        if case .exit(let code) = event {
                            let result = output.result(exitCode: code)
                            await notification.notifyIfNeeded(name: entryName, result: result)
                            // A background entry keeps only its latest *completed* run, so
                            // clear + register happen atomically here on `.exit` (one
                            // transaction). Doing it on exit — rather than clearing up front —
                            // means a run that fails to spawn (the `catch` below) leaves the
                            // prior successful record intact instead of wiping it. Best-effort:
                            // a history failure is logged, never aborts the completed run. The
                            // history Service owns record assembly + timestamping; the UseCase
                            // only stages it.
                            let record = history.makeRunRecord(
                                forEntry: entryID, named: entryName, command: domainCommand, result: result
                            )
                            await Self.persistBestEffort(
                                "run-history update failed for entry \(entryID)",
                                db: db, diagnostics: diagnostics
                            ) { tx in
                                try tx.deleteAllRuns(forEntry: entryID)
                                try tx.registerRun(record)
                            }
                        }
                        continuation.yield(CommandOutputResponse(from: event))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    // Consumer stopped (menu closed): not a failure — stay silent.
                    continuation.finish()
                } catch {
                    // Spawn/stream failure. Mirror the AppleScript path and OpenEntryUseCase:
                    // surface it to the user instead of finishing silently.
                    await notification.notifyFailure(name: entryName, error: error)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }

    /// Runs a best-effort run-history mutation in its own transaction. History is
    /// non-critical, so a failure must not abort the run — but it is logged
    /// (observable), never silently swallowed. Cancellation (the consumer dropped
    /// the stream) is not a failure and stays quiet.
    private static func persistBestEffort(
        _ context: String,
        db: any DBProtocol,
        diagnostics: any DiagnosticsLoggingProtocol,
        _ body: @escaping @Sendable (any Transaction) throws -> Void
    ) async {
        do {
            try await db.transaction(body)
        } catch is CancellationError {
            // Consumer dropped the stream — not a failure.
        } catch {
            diagnostics.warning("\(context): \(error.localizedDescription)")
        }
    }

    private func appleScriptStream(
        payload: AppleScriptPayload,
        entryName: String
    ) -> AsyncThrowingStream<CommandOutputResponse, Error> {
        let entry = payload.toDomain
        let appleScript = self.appleScript
        let notification = self.notification

        return AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    let result = try await appleScript.run(entry)
                    if let result, !result.isEmpty {
                        continuation.yield(.stdout(result))
                    }
                    await notification.notifyCompletion(name: entryName)
                    continuation.yield(.exit(code: 0, succeeded: true))
                    continuation.finish()
                } catch {
                    // Unify the stream's failure contract with the background path: a run
                    // that fails to execute is signalled by `finish(throwing:)`, never by a
                    // synthesized `.exit(succeeded: false)`. `.exit` means a clean
                    // termination; the consumer's catch surfaces the thrown error.
                    await notification.notifyFailure(name: entryName, error: error)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }
}

