import Foundation

final class CommandRunnerService: CommandRunnerServiceProtocol, Sendable {
    private let launcher: any CommandLauncherRepositoryProtocol

    init(launcher: any CommandLauncherRepositoryProtocol) {
        self.launcher = launcher
    }

    func perform(_ entry: CommandEntry, preference: TerminalPreference, currentDirectory: URL) async throws {
        switch entry.sink {
        case .background:
            // Background commands stream their output via `stream(_:)`
            // (`RunStreamingEntryUseCase`) and must never reach this open path.
            throw OperationError.invalidItem(
                reason: "background commands stream via the result window, not the open path"
            )

        case .terminal:
            // The terminal + launch mode comes from the global preference the UseCase
            // resolved; only the two scriptable terminals can actually receive a command.
            switch preference.selection {
            case .known(let app):
                try await launcher.runCommandInTerminal(
                    commandLine: entry.line,
                    directories: Self.directories(for: entry, currentDirectory: currentDirectory),
                    bundleIdentifier: app.bundleIdentifier,
                    launchMode: preference.launchMode
                )
            case .other(_, let name):
                throw OperationError.terminalLaunchFailed(
                    reason: "\(name) can't run commands — only Terminal.app and iTerm2 are supported"
                )
            }
        }
    }

    func stream(_ entry: CommandEntry, currentDirectory: URL) -> any AsyncSequence<CommandOutputEvent, Error> {
        switch entry.sink {
        case .background:
            return launcher.streamCommandInBackground(
                commandLine: entry.line,
                directories: Self.directories(for: entry, currentDirectory: currentDirectory)
            )
        case .terminal:
            // Terminal runs hand off to the terminal app — nothing to stream.
            return AsyncThrowingStream { $0.finish() }
        }
    }

    /// Bundles the entry's resolved working directory and the global current directory for
    /// the launcher. The working-directory string is already resolved by the UseCase (the
    /// `<WORKING_DIRECTORY>` sentinel, if any, has been replaced with the current
    /// directory), so a fixed path or `nil` reaches here.
    private static func directories(for entry: CommandEntry, currentDirectory: URL) -> CommandDirectories {
        let workingDirectory = entry.workingDirectory.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        return CommandDirectories(workingDirectory: workingDirectory, currentDirectory: currentDirectory)
    }
}
