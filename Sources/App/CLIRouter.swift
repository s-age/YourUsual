import Foundation

/// Routes the `your-usual` CLI subcommands. All verbs are **pure stdout** and touch no GUI
/// (no URL scheme, no `open`, no second instance):
///   • `your-usual cd [path]`    — resolve `[path]` against the cwd (no arg / blank = `$HOME`),
///                                 write the shared state file, and print the resolved absolute
///                                 path. The `yu` shell function uses the printed path to `cd`
///                                 the user's own shell (a child process cannot cd its parent).
///   • `your-usual cd-path`      — print the current resolved path (read-only, self-healing).
///   • `your-usual init <shell>` — print a shell snippet defining the `yu` function for the
///                                 user's rc (`eval "$(your-usual init zsh)"`); `zsh`/`bash`/`fish`.
///
/// Runs before any AppKit/Container setup (`main.swift`), so the CLI path stays cheap and never
/// boots the GUI. It instantiates the Infrastructure `CurrentDirectoryFileStore` directly — App
/// is the composition root, and a pre-boot helper doing direct I/O is the established pattern
/// (cf. the former `AppInstanceGuard`). Distribution: a Homebrew Cask `binary` stanza symlinks
/// this same executable onto PATH as `your-usual`.
enum CLIRouter {
    /// Handles a recognized CLI subcommand. Returns `true` when the args were a subcommand
    /// (the caller then exits without booting the GUI); `false` for a normal app launch.
    /// `store` is injectable for tests; production uses the shared file store.
    static func handle(_ arguments: [String],
                       store: any CurrentDirectoryStoreProtocol = CurrentDirectoryFileStore()) -> Bool {
        // arguments[0] is the executable path; a plain `.app` launch (LaunchServices may append
        // its own flags) has no recognized verb at [1], so it falls through and boots the GUI.
        guard arguments.count >= 2 else { return false }
        switch arguments[1] {
        case "cd":
            let resolved = resolve(arguments.count >= 3 ? arguments[2] : nil)
            // Persist failures (permissions, disk full) must NOT be swallowed: report them on
            // stderr so the user sees them, while stdout stays exactly the resolved path so the
            // `yu` function's `$(...)` capture is uncontaminated and the shell still cds.
            do {
                try store.savePath(resolved)
            } catch {
                FileHandle.standardError.write(Data(
                    "your-usual: failed to persist current directory: \(error.localizedDescription)\n".utf8))
            }
            print(resolved)
            return true
        case "cd-path":
            print(store.loadPath())
            return true
        case "init":
            print(initSnippet(shell: arguments.count >= 3 ? arguments[2] : "zsh"))
            return true
        default:
            return false
        }
    }

    /// Resolves a CLI path argument like shell `cd`: nil/blank → `$HOME`; `~`/`~/…` expanded;
    /// relative paths resolved against the CLI's cwd; the result standardized to an absolute path.
    ///
    /// NOTE: this duplicates the shell-`cd` semantics of `Domain/WorkingDirectoryResolver.resolve`
    /// (tilde expansion etc.). They cannot be shared — App may not import Domain — so keep their
    /// behaviour in sync: a change to tilde/relative handling here must mirror there (and vice
    /// versa). The key difference is intentional: this resolver is **cwd-relative** (the CLI has a
    /// working directory); `WorkingDirectoryResolver` is not (it also does a dir-existence → home
    /// fallback the CLI deliberately omits — see brief.md).
    static func resolve(_ arg: String?) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let arg, !arg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return home.path }
        let expanded = expandLeadingTilde(arg, home: home)
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        // `URL(fileURLWithPath:relativeTo:)` ignores `relativeTo` when the path is absolute.
        return URL(fileURLWithPath: expanded, relativeTo: cwd).standardizedFileURL.path
    }

    /// Expands a leading `~` / `~/…` against the home directory (mirrors shell behaviour);
    /// `~user` is intentionally not expanded.
    private static func expandLeadingTilde(_ path: String, home: URL) -> String {
        if path == "~" { return home.path }
        if path.hasPrefix("~/") { return home.path + "/" + path.dropFirst(2) }
        return path
    }

    /// Shell snippet defining `yu`. `cd "$(command your-usual cd "$@")"` updates the stored dir
    /// AND cds the user's own shell — a child process can't cd its parent, so the function must.
    static func initSnippet(shell: String) -> String {
        switch shell {
        case "fish":
            return "function yu; cd (command your-usual cd $argv); end"
        default:   // zsh, bash, sh
            return #"yu() { cd "$(command your-usual cd "$@")"; }"#
        }
    }
}
