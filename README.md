# your-usual

A register-your-operations launcher for macOS.

`your-usual` lives in your menu bar and runs the things you do all the time —
opening files and folders in the app of your choice, running shell commands and
AppleScripts, nudging a value with a slider. You register them once; they're a
click away from then on.

And because every command is just a plain shell one-liner, you no longer have to
be fluent at the command line to build your set: in the age of AI assistants,
you can have one write the command for you, paste it in, and keep it here to run
whenever you like. The CLI's power, without the CLI's learning curve.

> **You're responsible for what you register.** A command you paste in — whether
> you wrote it or an AI did — runs with your full privileges. Make sure it does
> only what you expect and nothing destructive (a stray `rm -rf` can wipe your
> files) **before** you register it. If you can't read a command well enough to
> judge it, don't run it. See [Security model](#security-model--please-read).

## A launcher you build, not one you search

Spotlight-style launchers are **search boxes**: they index your whole machine so
you can type a few letters and find anything. `your-usual` is the opposite. You
**register** the handful of things you actually reach for, and they stay put.
The set is fixed because *you* fixed it — so there's nothing to index, nothing
to fuzzy-match, and no ranking to second-guess. Your usual is right where you
left it.

You reach your registered entries two ways:

- **From the menu bar** — a click-through list, always one click away.
- **From a Pad** — a floating panel of buttons and sliders you summon when you
  want it.

## What you can register

Add entries in **Settings**. Each entry is one of:

- **File / Directory** — open a file or folder in the application of your choice
  (Finder by default).
- **Command** — run a shell command, either in the working directory you set on
  the entry or in a directory you pick. A command runs one of two ways:
  - **Run in background** — no console window opens; the command runs quietly
    (result delivered as a notification). For non-interactive commands.
  - **Run in terminal** — the command runs in the terminal app you chose, where
    you can watch it and type back. For interactive commands that prompt you and
    wait for input, or anything you want to keep driving by hand.
- **AppleScript** — run a registered AppleScript.
- **Slider** — a **Pad-only** command. It always runs in the background and
  takes exactly one numeric value through a `<VALUE>` placeholder, re-running
  the command as you drag (see [Sliders](#sliders)).

### Terminal app

For **Run in terminal**, choose how the command opens:

- Use the **standard Terminal**, **iTerm2**, or **any terminal app** you name.
- Window/tab behaviour:
  1. **Always a new window**
  2. **Always a new tab**
  3. **A new tab the first time, then reuse that tab**

  iTerm2 supports all three; the standard Terminal supports **1 and 3**.

### Current directory

A command's working directory can be **fixed** (a path you set) or **dynamic**.
Turn on **Use Current** and the command runs in a single, app-wide *current
directory* instead — change it once and every "Use Current" command follows.
Handy when you want to point the same set of commands at whichever project
you're in right now (e.g. `git status` across several repos without registering
one entry per repo).

## The menu bar

The menu bar lists the entries you added in Settings, ready to run with a click.
It shows everything **except** entries you've marked *don't show in the menu bar*
and **except** sliders (those live on Pads). The menu bar is also where you
**open Pads**: you can have several open at once, and choosing a Pad that's
already open toggles it closed.

## Pads

A Pad is a floating grid you lay out yourself:

- Choose the **number of buttons** across and down, **merge** cells into larger
  ones (rectangular merges only), and set each cell's **icon** and **background
  colour**.
- Cells hold **buttons** (commands that need no parameter) and **sliders**
  (commands that take one numeric value). The only variable input a Pad command
  takes is the [current directory](#current-directory).
- A slider can run **horizontally or vertically**, but it needs room: at least
  **two buttons' worth** of space.

Because a Pad never activates the app, it works as an on-screen control surface
— something close to a Stream Deck — that you can operate without the app you're
working in losing focus.

> **A Pad is a *pointer* surface, not a *touch* surface.** macOS does not accept
> touchscreen input on any display: a touch-capable external monitor is ignored
> as a touch device, and an iPad used as a second screen over Sidecar takes only
> the Apple Pencil and trackpad gestures, not finger taps. So you drive a Pad
> with the mouse, trackpad, or Pencil — not by tapping it like a physical Stream
> Deck. What a Pad keeps from that comparison is the one thing that matters here:
> it never pulls the app you're working in out of the foreground.

### Sliders

A slider runs a command containing a `<VALUE>` placeholder, substituting the
slider's value as you drag. You define the range (min / max / step) and an
initial position.

A slider you can try the moment you install, on any Mac:

```sh
osascript -e 'set volume output volume <VALUE>'
```

Set the range to `0`–`100` and drag — your system output volume follows the
knob. It's the quickest way to *feel* what a slider does before you wire one up
to brightness, a window manager, OBS, or anything else that takes a number.

> **Sliders are senders, not gauges.** A slider does **not** read or display the
> current state of whatever it controls — it has no "before" value to sync. It
> simply *sends the value you drag it to*. The initial position is just where
> the knob starts (default: the middle); operating it makes the value what you
> set.

> **Sliders fire commands, so they're not truly real-time.** Each value you drag
> through spawns a process (e.g. `osascript`), and the OS takes a moment to
> apply it. Expect a small lag and some coalescing of intermediate values rather
> than the frame-tight tracking of a native volume HUD — `your-usual` issues
> system calls, it doesn't ride a hardware bus. It's responsive enough to dial a
> value in by feel; it is not a real-time fader.

## Security model — please read

**Registered commands run with your full user privileges.** A command item is a
single command-line string, executed verbatim through your login shell
(`<login-shell> -l -c`) — in the background, or handed to your chosen terminal.
This is intentional: it lets you use redirection, pipes, `~`, globs, and your
normal `PATH`, exactly as if you typed the command yourself.

What this means for you:

- **You run these commands at your own risk.** The app does not sandbox or vet
  them — registering a command is the same as running it in your own terminal.
- **Confirming a command is safe is your responsibility.** Before you register
  anything, satisfy yourself that it does only what you intend and nothing
  destructive (deleting files, overwriting data, mass operations like
  `rm -rf`). This holds doubly for commands an AI assistant generated for you:
  read them, understand them, and run them only once you're sure. The author and
  distributors of `your-usual` accept no liability for what your registered
  commands do.
- **Register only commands you trust.** Treat the registry like your shell
  history or a personal script: anything you put there can read, modify, or
  delete your files and reach the network with your permissions.
- The app ships **unsandboxed by design** (running arbitrary commands requires
  it), via Developer ID + Homebrew Cask — never the Mac App Store.

You — the person registering and clicking the command — are the operator. There
is no untrusted third party in this flow, so the usual "command injection" threat
does not apply; the responsibility for what a command does is simply yours.

## Install

Install from the personal Homebrew tap:

```sh
brew install --cask s-age/your-usual/your-usual
```

That single line taps `s-age/homebrew-your-usual` and installs the cask in one
step; the DMG is Developer ID-signed and notarized, so Gatekeeper opens it
cleanly. Later upgrades come through `brew upgrade --cask your-usual`.

The cask also exposes a small `your-usual` command on your `PATH` (used to set
the app-wide [current directory](#current-directory) from a shell).

**Requirements:** macOS 15 (Sequoia) or later, on **Apple Silicon**.

## Building from source

This is a Swift Package Manager project.

```sh
git clone https://github.com/s-age/YourUsual.git
cd YourUsual
swift build                    # build
swift test                     # run tests
./Scripts/build.sh --install   # build a signed app bundle and install to /Applications
```

`./Scripts/release.sh` produces a Developer ID-signed, notarized DMG for cask
distribution.

## License

Released under the [MIT License](LICENSE).
