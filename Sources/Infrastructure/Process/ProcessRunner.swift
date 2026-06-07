import Foundation
import os
import Synchronization

/// Runs a registered command in the background, capturing stdout/stderr/exit code.
///
/// The command line is executed through the user's login shell (`-l -c`) so it
/// inherits the same `PATH`/environment as a terminal (a `launchd`-spawned GUI
/// app otherwise gets a minimal `PATH` without Homebrew's `/opt/homebrew/bin`),
/// and users can rely on shell features (redirection, pipes, `~`, globs, PATH
/// lookup). This intentionally
/// passes a shell string — see the "shell execution" note in `CLAUDE.md` /
/// `arch-infrastructure.md`: registered commands are author = operator, so the
/// usual injection threat model does not apply.
///
/// The blocking `waitUntilExit()` is offloaded to a detached task so it never
/// blocks the cooperative executor.
final class ProcessRunner: ProcessRunnerProtocol, Sendable {
    private static let log = Logger(subsystem: "com.yourusual.app", category: "ProcessRunner")

    /// Hard ceiling on in-flight stream chunks. The drain has no backpressure (it reads
    /// the pipe to EOF as fast as the child writes), so with the default `.unbounded`
    /// policy a runaway producer (`yes`) could grow the stream's buffer without bound,
    /// independently of the consumer's `BoundedLineBuffer` line cap. `.bufferingNewest`
    /// drops the *oldest* queued chunk on overflow — semantically lossless here because
    /// the consumer only retains trailing lines anyway, and the terminal `.exit` chunk
    /// is the newest so it is never the one dropped.
    private static let streamBufferChunks = 256

    /// The user's login shell (e.g. `/bin/zsh`), falling back to `/bin/sh`.
    ///
    /// Resolved via `getpwuid` and run as a login shell (`-l`) so background
    /// commands source the user's profile and see the same `PATH`/environment
    /// as a terminal — otherwise a `launchd`-spawned GUI app's minimal `PATH`
    /// omits Homebrew's `/opt/homebrew/bin` and tools like `gh` fail with
    /// "command not found".
    ///
    /// Resolved exactly once via a `static let`: `getpwuid` is **not reentrant**
    /// (it returns a pointer into a shared static buffer), so calling it on every
    /// run from concurrently-launched commands would race. Swift guarantees the
    /// `static let` initializer runs once under a thread-safe `dispatch_once`, so
    /// the single `getpwuid` call is never concurrent.
    private static let loginShell: String = {
        guard let cString = getpwuid(getuid())?.pointee.pw_shell else { return "/bin/sh" }
        let shell = String(cString: cString)
        return shell.isEmpty ? "/bin/sh" : shell
    }()

    /// Yields stdout/stderr slices as the child produces them,
    /// followed by a terminal `.exit` chunk.
    ///
    /// Concurrency: `Process`/`Pipe`/`FileHandle` are non-`Sendable`, so they are
    /// created, owned, and destroyed entirely inside one detached task. The only
    /// things crossing the task boundary are the `Sendable` continuation and
    /// `CommandStreamChunkDTO` values. The two pipe drains run concurrently to
    /// avoid the ~64 KB pipe-buffer deadlock; each rebuilds a `FileHandle` from a
    /// bare `Int32` fd inside its own task, so no non-`Sendable` handle is
    /// captured across the boundary. A `Mutex`-guarded process handle lets the
    /// `onTermination` callback terminate the child (SIGTERM then SIGKILL — see
    /// `ProcessHandle.terminate`) if the consumer cancels.
    func stream(commandLine: String,
                directories: CommandDirectoriesDTO) -> AsyncThrowingStream<CommandStreamChunkDTO, Error> {
        let workingDirectory = directories.workingDirectory
        let currentDirectory = directories.currentDirectory
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(Self.streamBufferChunks)) { continuation in
            let handle = ProcessHandle()
            let task = Task.detached(priority: .userInitiated) {
                let process = Process()
                process.executableURL = URL(filePath: Self.loginShell)
                process.arguments = ["-l", "-c", commandLine]
                // Run in the entry's working directory when set, otherwise the global current
                // directory (the persisted "usual" dir set via `your-usual cd`). Previously
                // only `workingDirectory` set the cwd and the current dir was export-only.
                process.currentDirectoryURL = workingDirectory ?? currentDirectory
                // Also inject the global current directory under YOUR_USUAL_CURRENT_DIRECTORY,
                // keeping the rest of the inherited environment intact (the login shell
                // `-l` still re-sources the profile to fix PATH). Kept for backward-compat with
                // commands that reference $YOUR_USUAL_CURRENT_DIRECTORY explicitly.
                process.environment = ProcessInfo.processInfo.environment.merging(
                    [CommandEnvironment.currentDirectoryKey: currentDirectory.path]
                ) { _, injected in injected }

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.finish(
                        throwing: OperationError.commandFailed(exitCode: -1, stderr: error.localizedDescription)
                    )
                    return
                }
                handle.store(process)
                // Close the cancellation window: a cancel between `run()` and `store()`
                // missed `onTermination`'s teardown, so re-check here. Route through
                // `handle.terminate()` (not a bare `process.terminate()`) so this path
                // gets the same SIGTERM→SIGKILL escalation as `onTermination` — a child
                // ignoring SIGTERM is still force-killed, symmetric with the other path.
                if Task.isCancelled { handle.terminate() }

                let outFD = outPipe.fileHandleForReading.fileDescriptor
                let errFD = errPipe.fileHandleForReading.fileDescriptor

                // Drain both pipes concurrently — reading one to EOF before the
                // other deadlocks once the child fills the unread pipe's buffer.
                async let outDone: Void = Self.drain(fd: outFD) { continuation.yield(.stdout($0)) }
                async let errDone: Void = Self.drain(fd: errFD) { continuation.yield(.stderr($0)) }
                _ = await (outDone, errDone)

                // Both readers hit EOF, so all output is flushed — only now report exit.
                process.waitUntilExit()
                continuation.yield(.exit(process.terminationStatus))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                handle.terminate()
            }
        }
    }

    /// Drains a pipe by fd to EOF, decoding each available slice to UTF-8 and
    /// handing it to `onChunk`. The `FileHandle` is rebuilt from the fd inside
    /// this detached task so no non-`Sendable` handle crosses a task boundary;
    /// `closeOnDealloc: false` leaves ownership with the owning `Pipe`.
    private static func drain(fd: Int32, _ onChunk: @Sendable @escaping (String) -> Void) async {
        await Task.detached(priority: .userInitiated) {
            let reader = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            // Bytes of an incomplete trailing UTF-8 sequence carried into the next read,
            // so a multibyte character split across a 64 KB read boundary is decoded once
            // it is whole instead of becoming a U+FFFD replacement character.
            var carry = [UInt8]()
            while true {
                // `read(upToCount:)` surfaces I/O errors as catchable Swift errors;
                // `availableData` raises an uncatchable `NSFileHandleOperationException`
                // on a read fault, which would crash the app. On a read error we stop
                // draining (the process still reports its exit) rather than trap — log it
                // and emit an in-band marker so the truncation is visible to the user too,
                // not only in the log (the consumer otherwise sees a clean, complete stream).
                let data: Data?
                do {
                    data = try reader.read(upToCount: 1 << 16)
                } catch {
                    let reason = error.localizedDescription
                    Self.log.error("Pipe drain read failed; stopping drain: \(reason, privacy: .public)")
                    onChunk("\n⚠️ [output truncated: pipe read error]\n")
                    break
                }
                guard let data, !data.isEmpty else { break }   // nil/empty: EOF (write end closed)
                if carry.isEmpty {
                    // Fast path (the overwhelming majority): the previous read ended on a
                    // complete character, so decode this `Data` slice directly — no copy
                    // into an intermediate array — and hold back only an incomplete tail.
                    let holdBack = incompleteUTF8TrailingCount(data)
                    let completeCount = data.count - holdBack
                    if completeCount > 0 { onChunk(String(decoding: data.prefix(completeCount), as: UTF8.self)) }
                    if holdBack > 0 { carry = Array(data.suffix(holdBack)) }
                } else {
                    // Rare: a multibyte character straddled the previous boundary, so stitch
                    // the held-over bytes (≤ 3) onto this read before decoding.
                    var bytes = carry
                    bytes.append(contentsOf: data)
                    let split = bytes.count - incompleteUTF8TrailingCount(bytes)
                    if split > 0 { onChunk(String(decoding: bytes[0..<split], as: UTF8.self)) }
                    carry = Array(bytes[split...])
                }
            }
            // Flush held-over bytes. Normally empty; non-empty only when the stream
            // genuinely ended mid-sequence (truncated output) — there a replacement
            // character is the faithful result.
            if !carry.isEmpty { onChunk(String(decoding: carry, as: UTF8.self)) }
        }.value
    }

    /// Count of trailing bytes that begin an *incomplete* UTF-8 sequence (0 when the
    /// buffer ends on a complete one), so a split multibyte character can be held back
    /// until the next read supplies its continuation bytes.
    private static func incompleteUTF8TrailingCount<C: RandomAccessCollection>(
        _ bytes: C
    ) -> Int where C.Element == UInt8 {
        let lookback = min(4, bytes.count)
        var i = 1
        while i <= lookback {
            let byte = bytes[bytes.index(bytes.endIndex, offsetBy: -i)]
            if byte & 0b1100_0000 != 0b1000_0000 {   // a lead byte (or ASCII), not a continuation
                let expected: Int
                if byte & 0b1000_0000 == 0 { expected = 1 }
                else if byte & 0b1110_0000 == 0b1100_0000 { expected = 2 }
                else if byte & 0b1111_0000 == 0b1110_0000 { expected = 3 }
                else if byte & 0b1111_1000 == 0b1111_0000 { expected = 4 }
                else { return 0 }                     // invalid lead byte — let the decoder surface it
                return i < expected ? i : 0           // fewer bytes than the sequence needs → hold back
            }
            i += 1
        }
        return 0   // only continuation bytes within the lookback window — let the decoder handle it
    }
}

/// Sendable holder for the running `Process`, so the stream's `onTermination`
/// callback can terminate the child without capturing the non-`Sendable` process
/// directly. Backed by `Mutex` rather than a concurrency escape hatch.
private final class ProcessHandle: Sendable {
    /// Grace period between SIGTERM and the SIGKILL escalation (seconds).
    private static let killGrace: Double = 3

    private let process: Mutex<Process?> = Mutex(nil)

    func store(_ process: Process) {
        self.process.withLock { $0 = process }
    }

    /// Tears the child down: SIGTERM first (lets it exit cleanly), then SIGKILL
    /// after a grace period if it is still alive. The escalation matters because a
    /// child that traps or ignores SIGTERM would otherwise keep the blocking
    /// `waitUntilExit()`/pipe drains running forever, leaking the Process, tasks,
    /// and pipes.
    ///
    /// Residual caveat: SIGKILL reaches only the direct child. A backgrounded
    /// grandchild that inherited the pipe's write end (e.g. `(sleep 1000 &)`) can
    /// still hold it open and defer EOF, so the drains may not unblock until that
    /// grandchild exits. Fully reaping a detached process group is out of scope for
    /// the author-is-operator command model; this is documented, not silently
    /// assumed away.
    func terminate() {
        let pid: pid_t? = process.withLock { current in
            guard current?.isRunning == true else { return nil }
            current?.terminate()            // SIGTERM
            return current?.processIdentifier
        }
        guard let pid else { return }
        Task.detached(priority: .utility) { [self] in
            try? await Task.sleep(for: .seconds(Self.killGrace))
            process.withLock { current in
                if current?.isRunning == true { kill(pid, SIGKILL) }
            }
        }
    }
}
