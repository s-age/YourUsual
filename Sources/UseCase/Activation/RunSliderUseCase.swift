import Foundation

/// Runs a slider's command for the given value, fire-and-forget: no notification, no run
/// history (unlike `RunStreamingEntryUseCase`). Called repeatedly while dragging (throttled
/// by Presentation) and once on release. Drains the background output stream silently — the
/// run is wanted only for its side effect, so output, exit code, and failures are discarded:
/// a high-frequency tick's failure must not alert (the next drag overwrites it).
final class RunSliderUseCase: AsyncUseCase, Sendable {
    private let command: any CommandRunnerServiceProtocol
    private let currentDirectory: any CurrentDirectoryServiceProtocol
    private let resolver: any WorkingDirectoryResolverProtocol

    init(
        command: any CommandRunnerServiceProtocol,
        currentDirectory: any CurrentDirectoryServiceProtocol,
        resolver: any WorkingDirectoryResolverProtocol
    ) {
        self.command = command
        self.currentDirectory = currentDirectory
        self.resolver = resolver
    }

    func execute(_ request: RunSliderRequest) async throws {
        guard case .slider(let slider) = request.entry.kind else {
            // A non-slider kind reaching here is a routing-invariant violation (only `.adjust`
            // entries are sent to this use case). Fail loud rather than run nothing silently.
            throw OperationError.misroutedEntry(reason: "\(request.entry.name) is not a slider")
        }
        // Product decision: sliders run in the global current directory (same as background
        // commands), so the currentDirectory/resolver dependency is load-bearing — not dead.
        let currentDir = resolver.resolve(currentDirectory.current().path)
        let domainCommand = slider.toCommandDomain(value: request.value, currentDirectory: currentDir)
        // Drain silently: no notify, no history. We only need the side effect.
        for try await _ in command.stream(domainCommand, currentDirectory: currentDir) {}
    }
}
