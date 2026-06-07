import Foundation
import Observation

/// Command target — owns the command line, working directory, and the Action
/// (Run in background / terminal). Keeping `handlerKind` here means the parent's
/// Type picker can no longer reset it on a re-render.
@Observable
@MainActor
final class CommandEntryFormViewModel {
    enum HandlerKind: String, CaseIterable {
        case background
        case terminal
    }

    var commandLine = ""
    /// Defaults to the home directory; editable by hand or via the Browse button.
    var workingDirectory = ""

    var handlerKind: HandlerKind = .background

    private let resolveWorkingDirectory: ResolveWorkingDirectoryUseCaseProtocol

    init(resolveWorkingDirectory: ResolveWorkingDirectoryUseCaseProtocol) {
        self.resolveWorkingDirectory = resolveWorkingDirectory
        // Default the field to the home directory; editing a command overrides it.
        workingDirectory = (try? resolveWorkingDirectory.execute(.init(path: nil))) ?? ""
    }

    /// Prefill from an existing command entry when editing.
    func load(_ command: CommandPayload) {
        commandLine = command.commandLine
        if let stored = command.workingDirectory, !stored.isEmpty {
            workingDirectory = stored
        }
        switch command.sink {
        case .background:
            handlerKind = .background
        case .terminal:
            handlerKind = .terminal
        }
    }

    var availableHandlerKinds: [HandlerKind] { HandlerKind.allCases }

    /// Starting directory for the working-directory Browse panel: the currently
    /// entered directory if valid, otherwise the home directory.
    var browseDefaultDirectory: URL {
        let resolved = (try? resolveWorkingDirectory.execute(.init(path: workingDirectory)))
        return URL(fileURLWithPath: resolved ?? workingDirectory)
    }

    /// Whether the working directory is the dynamic current-directory sentinel.
    var isUsingCurrentDirectory: Bool { workingDirectory == WorkingDirectoryToken.current }

    /// Sets the working directory to the `<WORKING_DIRECTORY>` sentinel, so this command
    /// runs in the app's global current directory (set in Settings or via `your-usual cd`)
    /// instead of a fixed path.
    func useCurrentDirectory() { workingDirectory = WorkingDirectoryToken.current }

    func handleWorkingDirectoryImport(_ result: Result<URL, Error>) {
        // Intentionally drop .failure/cancel: cancel is normal, and a genuine
        // importer error (system file-dialog infra) is rare. This child form VM
        // has no error/alert channel; empty/invalid input is caught at submit by
        // the parent's validation. (Asymmetry with TerminalSettingsViewModel,
        // which surfaces errors via its actionError channel, is intentional.)
        guard case .success(let url) = result else { return }
        workingDirectory = url.path
    }

    func buildKind() -> EntryKindPayload {
        let sink: CommandSinkPayload = (handlerKind == .terminal) ? .terminal : .background
        return .command(CommandPayload(
            commandLine: commandLine,
            workingDirectory: workingDirectory.isEmpty ? nil : workingDirectory,
            sink: sink
        ))
    }
}
