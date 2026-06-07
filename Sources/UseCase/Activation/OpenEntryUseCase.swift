import Foundation

/// Opens a registered entry whose execution style is `.open` — browse targets and
/// `.terminal` commands. Entries that resolve to `.runAndStream` (`.background`
/// commands and AppleScript) are routed to `RunStreamingEntryUseCase` by the menu
/// and never reach here. If one arrives anyway it is a routing-invariant violation,
/// surfaced as an explicit error rather than silently run on the wrong path — and
/// the run-and-stream execution logic lives in exactly one place, not duplicated here.
final class OpenEntryUseCase: AsyncUseCase, Sendable {
    private let browse: any BrowseLauncherServiceProtocol
    private let command: any CommandRunnerServiceProtocol
    private let notification: any NotificationServiceProtocol
    private let terminalSettings: any TerminalSettingsServiceProtocol
    private let currentDirectory: any CurrentDirectoryServiceProtocol
    private let resolver: any WorkingDirectoryResolverProtocol

    init(
        browse: any BrowseLauncherServiceProtocol,
        command: any CommandRunnerServiceProtocol,
        notification: any NotificationServiceProtocol,
        terminalSettings: any TerminalSettingsServiceProtocol,
        currentDirectory: any CurrentDirectoryServiceProtocol,
        resolver: any WorkingDirectoryResolverProtocol
    ) {
        self.browse = browse
        self.command = command
        self.notification = notification
        self.terminalSettings = terminalSettings
        self.currentDirectory = currentDirectory
        self.resolver = resolver
    }

    func execute(_ request: OpenEntryRequest) async throws {
        switch request.entry.kind {
        case .browse(let payload):
            try await browse.launch(payload.toDomain)
        case .command(let payload) where payload.sink == .terminal:
            // The terminal owns its own output, so there is nothing to capture or
            // record here. Resolve the global terminal preference + current directory
            // through their owning Services and hand them to the runner — the runner
            // does not read either store. The `<WORKING_DIRECTORY>` sentinel (if used)
            // is resolved to the current directory here.
            do {
                let currentDir = resolver.resolve(currentDirectory.current().path)
                try await command.perform(
                    payload.toDomain(resolvingCurrentDirectory: currentDir),
                    preference: terminalSettings.current(),
                    currentDirectory: currentDir
                )
            } catch {
                await notification.notifyFailure(name: request.entry.name, error: error)
                throw error
            }
        case .command, .appleScript, .slider:
            // `.background` commands and AppleScript resolve to `.runAndStream` (executed by
            // `RunStreamingEntryUseCase`); a slider resolves to `.adjust` (executed by
            // `RunSliderUseCase`). None should reach the open path — arriving here means the
            // caller's routing (see `ExecutionStyle.resolve`) disagrees with this switch.
            throw OperationError.misroutedEntry(
                reason: "\(request.entry.name) is not an open entry"
            )
        }
    }
}
