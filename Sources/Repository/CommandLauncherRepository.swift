import Foundation

/// Runs a command — streamed in the background or handed to a terminal — backing
/// `CommandRunnerService`.
final class CommandLauncherRepository: CommandLauncherRepositoryProtocol, Sendable {
    private let processRunner: any ProcessRunnerProtocol
    private let terminalLauncher: any TerminalLauncherProtocol

    init(processRunner: any ProcessRunnerProtocol,
         terminalLauncher: any TerminalLauncherProtocol) {
        self.processRunner = processRunner
        self.terminalLauncher = terminalLauncher
    }

    func streamCommandInBackground(commandLine: String,
                                   directories: CommandDirectories) -> any AsyncSequence<CommandOutputEvent, Error> {
        // Lazily map the process chunk stream (DTO → entity) with no second buffer: a
        // `.map` is a pass-through view, so back-pressure and cancellation propagate to
        // the underlying `ProcessRunner.stream` (which owns the single buffer + the
        // process teardown). Re-wrapping in another `AsyncThrowingStream` here would add a
        // redundant buffer that re-holds every chunk.
        processRunner.stream(commandLine: commandLine,
                             directories: Self.toDTO(directories)).map(Self.toEvent)
    }

    /// Domain `CommandDirectories` → Infrastructure transport shape.
    private static func toDTO(_ directories: CommandDirectories) -> CommandDirectoriesDTO {
        CommandDirectoriesDTO(workingDirectory: directories.workingDirectory,
                              currentDirectory: directories.currentDirectory)
    }

    private static func toEvent(_ chunk: CommandStreamChunkDTO) -> CommandOutputEvent {
        switch chunk {
        case .stdout(let text): return .stdout(text)
        case .stderr(let text): return .stderr(text)
        case .exit(let code):   return .exit(code)
        }
    }

    func runCommandInTerminal(commandLine: String,
                              directories: CommandDirectories,
                              bundleIdentifier: String,
                              launchMode: TerminalLaunchMode) async throws {
        try await terminalLauncher.run(
            commandLine: commandLine,
            directories: Self.toDTO(directories),
            inTerminalBundleIdentifier: bundleIdentifier,
            launchMode: launchMode.rawValue
        )
    }
}
