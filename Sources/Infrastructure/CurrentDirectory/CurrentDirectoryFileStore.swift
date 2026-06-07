import Foundation

/// File-backed store for the global "usual" directory — the single source of truth shared by
/// the GUI (via DI) and the `your-usual cd` CLI (which instantiates this directly, pre-boot).
/// Holds one resolved absolute path + trailing newline at
/// `~/Library/Application Support/YourUsual/current-directory`. Build-independent name (not
/// `…app.dev`-namespaced like the SwiftData store) so the Homebrew-symlinked release CLI and
/// the installed app agree on one file.
///
/// Reads are tolerant and self-healing (missing/empty/unreadable → home, rewriting the
/// default) so deleting the file recreates the initial `cd "$HOME"` state on next access.
/// `Sendable` with no stored mutable state — the file is the source of truth and writes are
/// atomic (last-writer-wins, fine for a single user), so no `Mutex` is needed.
final class CurrentDirectoryFileStore: CurrentDirectoryStoreProtocol, Sendable {
    /// Shared on-disk location (used by DI and the CLI). Overridable in `init` for tests.
    static let defaultFileURL: URL = URL.applicationSupportDirectory
        .appending(path: "YourUsual", directoryHint: .isDirectory)
        .appending(path: "current-directory", directoryHint: .notDirectory)

    private let fileURL: URL

    init(fileURL: URL = CurrentDirectoryFileStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    private var homePath: String { FileManager.default.homeDirectoryForCurrentUser.path }

    func loadPath() -> String {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else {
            try? writeDefault()                    // self-heal (best-effort; a read must not fail)
            return homePath
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try? writeDefault()
            return homePath
        }
        return trimmed
    }

    func savePath(_ path: String?) throws {
        // Self-normalizes (trim, nil/blank → home) because the CLI writes here *bypassing*
        // `CurrentDirectoryService`, which performs the same trim + "blank → nil". The store
        // owns the final "nil/blank means home" meaning so a direct CLI write is consistent
        // with a GUI write. Keep the two normalizations in sync.
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty == false) ? trimmed! : homePath
        try write(value)
    }

    private func writeDefault() throws { try write(homePath) }

    private func write(_ value: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])               // match the registry store dir's 0700
        try (value + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
