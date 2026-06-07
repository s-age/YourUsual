import Foundation

/// Decides which directory a command should run in: the user's choice when it
/// names a real directory, otherwise the home directory. The "invalid → home"
/// rule lives here (business decision); the filesystem facts come from the
/// repository.
///
/// NOTE: the shell-`cd` semantics here (tilde expansion, blank → home) are mirrored by
/// `App/CLIRouter.resolve`, which the App layer cannot share with Domain (no upward import).
/// Keep the two in sync — a change to tilde handling here must be reflected there. The CLI
/// variant additionally resolves cwd-relative paths and omits the dir-existence → home fallback.
final class WorkingDirectoryResolver: WorkingDirectoryResolverProtocol, Sendable {
    private let repository: any FileSystemRepositoryProtocol

    init(repository: any FileSystemRepositoryProtocol) {
        self.repository = repository
    }

    func resolve(_ path: String?) -> URL {
        let home = repository.homeDirectory()
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return home
        }
        // Expand a leading `~` / `~/…` against the resolved home, the way a shell does — so a
        // tilde working-directory is honoured rather than silently failing to `isDirectory`
        // and falling back to home. Matches the command string's documented `~` support.
        // `URL(fileURLWithPath:)` does NOT expand `~`, hence this step. `~user` (another
        // user's home) is intentionally not expanded — rare, and it would need a passwd
        // lookup; it falls through to the invalid → home path below.
        let expanded = Self.expandingLeadingTilde(trimmed, home: home)
        let candidate = URL(fileURLWithPath: expanded)
        return repository.isDirectory(candidate) ? candidate : home
    }

    private static func expandingLeadingTilde(_ path: String, home: URL) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        guard path != "~" else { return home.path }
        return home.path + "/" + path.dropFirst(2)   // strip the leading "~/"
    }
}
