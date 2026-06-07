import Foundation

// Executable entry point. Dual-mode:
//   • `your-usual cd|cd-path|init …` — a CLI subcommand handled by `CLIRouter` (pure stdout,
//     no GUI: it reads/writes the shared current-directory state file directly) and exits.
//   • no recognized subcommand — boot the normal menu-bar app.
//
// The argv check runs before any AppKit/Container setup, so the CLI path stays cheap and
// never spins up a UI. (Distribution: a Homebrew Cask `binary` stanza symlinks this same
// executable onto PATH as `your-usual`.)
if CLIRouter.handle(CommandLine.arguments) {
    exit(0)
}

YourUsualApp.main()
