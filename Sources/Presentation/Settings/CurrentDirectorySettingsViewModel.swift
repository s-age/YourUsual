import Foundation
import Observation

/// Drives the global "Current Directory" settings pane: the directory commands run in,
/// exported as `YOUR_USUAL_CURRENT_DIRECTORY`. Persisted to a state file shared with the
/// `your-usual cd` CLI (survives relaunch); changes reflect the resolved path (home when
/// cleared or the chosen folder no longer exists).
@Observable
@MainActor
final class CurrentDirectorySettingsViewModel {
    private(set) var settings: CurrentDirectoryResponse?

    /// User-facing message for the most recent failed read/write/import, surfaced as a
    /// one-shot alert rather than nil-ing `settings` into a permanent spinner.
    var actionError: String?

    private let readCurrentDirectory: ReadCurrentDirectoryUseCaseProtocol
    private let setCurrentDirectory: SetCurrentDirectoryUseCaseProtocol

    init(
        readCurrentDirectory: ReadCurrentDirectoryUseCaseProtocol,
        setCurrentDirectory: SetCurrentDirectoryUseCaseProtocol
    ) {
        self.readCurrentDirectory = readCurrentDirectory
        self.setCurrentDirectory = setCurrentDirectory
    }

    func load() {
        do {
            settings = try readCurrentDirectory.execute(ReadCurrentDirectoryRequest())
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// The resolved current directory abbreviated with `~` for display.
    var displayPath: String {
        guard let path = settings?.path else { return "" }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    /// Handles the folder `.fileImporter` result: set the chosen directory. A cancelled
    /// importer stays silent; a genuine failure surfaces as `actionError`.
    func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        apply(path: url.path)
    }

    /// Clears the current directory back to "unset" (which resolves to home).
    func resetToHome() {
        apply(path: nil)
    }

    private func apply(path: String?) {
        do {
            settings = try setCurrentDirectory.execute(SetCurrentDirectoryRequest(path: path))
        } catch {
            actionError = error.localizedDescription
        }
    }
}
