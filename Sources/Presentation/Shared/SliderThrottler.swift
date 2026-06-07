import Foundation
import Synchronization

/// Trailing throttle for slider drags: coalesces rapid value changes to at most one
/// `action` per `interval` (default 0.5s) and always flushes the final value on `commit`.
/// The interval is intentionally coarse: a slider `action` is an external command whose cost
/// is dominated by spawning the login shell (~250ms locally) and, for network-backed commands
/// (e.g. a Hue bridge over HTTP), by round-trip latency. The floor is set for the slowest
/// expected command so runs don't queue up behind the drag; `commit` still guarantees the
/// final value lands exactly.
/// Keyed per slider id so multiple sliders don't interfere. `action`s are async (each runs
/// a slider's command use case). Swift 6 strict-concurrency safe via `Mutex` — the codebase's
/// mandated synchronization primitive, so no concurrency escape hatch is needed.
///
/// Beyond window coalescing, runs are **serialized and conflated per id**: at most one run is
/// in flight and at most one is queued behind it, and a newer submission replaces the queued
/// one. So even though an `action` drives an external process (osascript etc.) whose completion
/// order is otherwise unguaranteed, runs never overlap and the latest submitted value is the
/// one that ultimately runs — the slider can't settle on a stale value. When submissions pile
/// up behind a slow or timed-out run, the intermediate ones are dropped (only the newest
/// survives), which bounds how many runs can pile up — and, in the abandoned-run case
/// `runBounded` guards, how many can leak.
final class SliderThrottler: Sendable {
    private struct State {
        var lastFired: Date?
        var pending: Task<Void, Never>?              // deferred trailing tick (window coalescing)
        var queued: (@Sendable () async -> Void)?    // latest run waiting behind the active one
        var draining = false                          // is the per-id drain loop active
    }

    private let interval: TimeInterval
    private let runTimeout: TimeInterval
    private let state: Mutex<[UUID: State]>
    private let clock: @Sendable () -> Date    // injected for testability

    init(interval: TimeInterval = 0.5,
         runTimeout: TimeInterval = 5,
         clock: @escaping @Sendable () -> Date = { Date() }) {
        self.interval = interval
        self.runTimeout = runTimeout
        self.state = Mutex([:])
        self.clock = clock
    }

    /// Schedule a throttled tick for `id`. Leading + trailing: the first tick of a window
    /// fires immediately; further ticks within `interval` defer the latest `action` to a
    /// single trailing fire (replacing any previously deferred one) so only the most recent
    /// value runs. No value is lost across the window — the tail is guaranteed by either the
    /// trailing fire or a `commit`.
    func tick(_ id: UUID, action: @escaping @Sendable () async -> Void) {
        let fireNow = state.withLock { dict -> Bool in
            var entry = dict[id] ?? State()
            let now = clock()
            if let last = entry.lastFired, now.timeIntervalSince(last) < interval {
                // Within the window: defer to a trailing fire, replacing any earlier
                // deferral so only the latest value runs.
                entry.pending?.cancel()
                let delay = interval - now.timeIntervalSince(last)
                entry.pending = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    self?.runSerially(id, action)
                    self?.markFired(id)
                }
                dict[id] = entry
                return false
            }
            // First tick, or the window has elapsed: fire immediately.
            entry.lastFired = now
            entry.pending?.cancel()
            entry.pending = nil
            dict[id] = entry
            return true
        }
        if fireNow { runSerially(id, action) }
    }

    /// Flush immediately and reset `id`'s window — call on drag end so the final value runs.
    /// Cancels any deferred trailing tick (its value is superseded by this final one) and
    /// runs `action` now, guaranteeing the last value is never dropped.
    func commit(_ id: UUID, action: @escaping @Sendable () async -> Void) {
        state.withLock { dict in
            var entry = dict[id] ?? State()
            entry.pending?.cancel()
            entry.pending = nil
            entry.lastFired = clock()
            dict[id] = entry
        }
        runSerially(id, action)
    }

    /// Enqueue `action` as `id`'s next run, coalescing to the latest: at most one run is in
    /// flight and at most one waits behind it, and a newer submission replaces the waiting one.
    /// A burst of submissions while a run is busy therefore collapses to "the active run, then
    /// the most recent value" — intermediates are dropped. This is the right slider semantic
    /// (track the latest position) and bounds how many runs can pile up behind a slow or
    /// timed-out run: only the newest survives, so far fewer runs ever start (and far fewer can
    /// leak in the abandoned-run case `runBounded` guards). `action` is `() async -> Void` (the
    /// caller swallows its own errors), so the loop never breaks on a thrown error.
    private func runSerially(_ id: UUID, _ action: @escaping @Sendable () async -> Void) {
        let startDrain = state.withLock { dict -> Bool in
            var entry = dict[id] ?? State()
            entry.queued = action            // coalesce: the newest submission replaces any waiting one
            let shouldStart = !entry.draining
            if shouldStart { entry.draining = true }
            dict[id] = entry
            return shouldStart
        }
        if startDrain { drain(id) }
    }

    /// Per-id drain loop: runs the latest queued action (bounded by `runBounded`), then repeats
    /// while newer ones have arrived, and exits when the queue is empty. Taking the queued
    /// action and clearing `draining` happen in one locked step, so a submission can never be
    /// lost to a loop that is exiting: a concurrent `runSerially` either sees `draining == true`
    /// and just enqueues, or sees it `false` and restarts the loop.
    private func drain(_ id: UUID) {
        Task { [weak self] in
            while true {
                guard let self else { break }
                let next = state.withLock { dict -> (@Sendable () async -> Void)? in
                    guard var entry = dict[id] else { return nil }
                    let action = entry.queued
                    entry.queued = nil
                    if action == nil { entry.draining = false }   // nothing left — let the loop exit
                    dict[id] = entry
                    return action
                }
                guard let next else { break }
                await Self.runBounded(next, timeout: runTimeout)
            }
        }
    }

    /// Run `action`, but stop waiting for it after `timeout`. On overrun the action's task is
    /// cancelled — which tears down the underlying process via the command stream's termination
    /// handler (`ProcessRunner` escalates SIGTERM→SIGKILL) — and we deliberately stop awaiting
    /// it. A run that misses its deadline is treated as dead; abandoning it (rather than
    /// `await`ing its `.value`) is what guarantees the per-id serial chain always advances, even
    /// in the pathological case where cancellation cannot fully tear the process down (e.g. a
    /// backgrounded grandchild holding the pipe's write end open, deferring EOF forever).
    private static func runBounded(_ action: @escaping @Sendable () async -> Void,
                                   timeout: TimeInterval) async {
        // The timer returns either when the deadline elapses, or early when `work` finishes and
        // cancels it. We await the timer (never `work.value` unconditionally), so a work task
        // that ignores cancellation can never block us past the deadline.
        let timer = Task<Void, Never> {
            do { try await Task.sleep(for: .seconds(timeout)) }
            catch { return }   // cancelled because `action` finished first
        }
        let work = Task<Void, Never> {
            await action()
            timer.cancel()     // action done → wake the timer immediately
        }
        await timer.value
        work.cancel()          // tears down a still-running (overrun) action; no-op otherwise
    }

    /// Record the time a deferred trailing tick actually fired, so the next tick opens a
    /// fresh window from that point.
    private func markFired(_ id: UUID) {
        state.withLock { $0[id]?.lastFired = clock() }
    }
}
