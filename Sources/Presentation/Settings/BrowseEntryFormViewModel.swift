import Foundation
import Observation

/// Browse target (a file/directory opened with an app) — owns its own path + app
/// fields so type switching in the parent form never touches (or clobbers) this state.
/// Named for the domain concept it builds (`EntryKindPayload.browse`); the user-facing
/// picker still reads "File / Directory".
@Observable
@MainActor
final class BrowseEntryFormViewModel {
    var path = ""

    var appBundleIdentifier = "com.apple.finder"

    private let resolveWorkingDirectory: ResolveWorkingDirectoryUseCaseProtocol
    private let resolveAppBundleIdentifier: ResolveAppBundleIdentifierUseCaseProtocol

    init(
        resolveWorkingDirectory: ResolveWorkingDirectoryUseCaseProtocol,
        resolveAppBundleIdentifier: ResolveAppBundleIdentifierUseCaseProtocol
    ) {
        self.resolveWorkingDirectory = resolveWorkingDirectory
        self.resolveAppBundleIdentifier = resolveAppBundleIdentifier
    }

    /// Prefill from an existing browse entry when editing.
    func load(_ browse: BrowsePayload) {
        path = browse.path
        switch browse.app {
        case .default:
            appBundleIdentifier = "com.apple.finder"
        case .app(let bundleIdentifier):
            appBundleIdentifier = bundleIdentifier
        }
    }

    /// Starting directory for the path Browse panel: the parent of the entered
    /// path if valid, otherwise the home directory.
    var pathBrowseDefaultDirectory: URL {
        guard !path.isEmpty else {
            return URL(fileURLWithPath: (try? resolveWorkingDirectory.execute(.init(path: nil))) ?? "")
        }
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        let resolved = try? resolveWorkingDirectory.execute(.init(path: parent.path))
        return URL(fileURLWithPath: resolved ?? parent.path)
    }

    func handlePathImport(_ result: Result<URL, Error>) {
        // Intentionally drop .failure/cancel: cancel is normal, and a genuine
        // importer error (system file-dialog infra) is rare. This child form VM
        // has no error/alert channel; empty/invalid input is caught at submit by
        // the parent's validation. (Asymmetry with TerminalSettingsViewModel,
        // which surfaces errors via its actionError channel, is intentional.)
        guard case .success(let url) = result else { return }
        path = url.path
    }

    func handleAppImport(_ result: Result<URL, Error>) {
        // Intentionally drop .failure/cancel — see handlePathImport.
        guard case .success(let url) = result else { return }
        // Only assign when a bundle id actually resolves: if the picked app has
        // no readable bundle identifier, leave the current (possibly valid) value
        // untouched rather than clobbering it to "". An empty/invalid selection
        // is still caught at submit by the parent's validation. The bundle read is
        // framework I/O (`Bundle`/`NSWorkspace`), so it runs in Infrastructure via
        // this use case rather than in the View (mirrors the terminal browse path).
        // `try?` flattens the use case's `String?` result: nil on a throw or an
        // unresolvable app, a value only when a bundle id was found.
        guard let bundleIdentifier = try? resolveAppBundleIdentifier.execute(
            ResolveAppBundleIdentifierRequest(url: url)
        ) else { return }
        appBundleIdentifier = bundleIdentifier
    }

    func buildKind() -> EntryKindPayload {
        .browse(BrowsePayload(path: path, app: .app(bundleIdentifier: appBundleIdentifier)))
    }
}
