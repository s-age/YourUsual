import XCTest
import Synchronization
@testable import YourUsual

/// Verifies the guarantees the slider drag relies on: rapid ticks within a window coalesce to a
/// single trailing run, `commit` always flushes the final value (no dropped tail), runs are
/// conflated per id (at most one queued — the latest — behind the active run), and a run that
/// overruns its timeout is abandoned without wedging later runs. A fixed/controlled `clock`
/// makes the window decision deterministic; the trailing fire still uses a real (small)
/// `interval` sleep.
final class SliderThrottlerTests: XCTestCase {

    /// `Mutex` is non-copyable, so it can't be captured into the `@Sendable` closures the
    /// throttler runs. Wrap it in a Sendable reference type whose pointer *is* copyable, so
    /// every `record` closure shares the one underlying log.
    private final class FiredLog: Sendable {
        let tags = Mutex<[String]>([])
    }

    /// Records each fired tag in order, safe to mutate from the throttler's async tasks.
    private let fired = FiredLog()

    private func record(_ tag: String, _ expectation: XCTestExpectation) -> @Sendable () async -> Void {
        let log = fired
        return {
            log.tags.withLock { $0.append(tag) }
            expectation.fulfill()
        }
    }

    // The first tick fires immediately; subsequent ticks inside the window are deferred and
    // coalesce to one trailing fire carrying the latest value (the intermediate one is
    // dropped, not run twice).
    func test_tick_coalescesWindowToSingleTrailingFire() async {
        let now = Mutex(Date(timeIntervalSince1970: 1000))
        let throttler = SliderThrottler(interval: 0.05, clock: { now.withLock { $0 } })
        let id = UUID()

        let firstFired = expectation(description: "first tick fires immediately")
        throttler.tick(id, action: record("first", firstFired))
        await fulfillment(of: [firstFired], timeout: 1)

        // Clock held inside the window, so both following ticks are deferred; the second is
        // replaced by the third before it can fire.
        let droppedShouldNotRun = expectation(description: "coalesced tick is dropped")
        droppedShouldNotRun.isInverted = true
        let trailingFired = expectation(description: "latest deferred value fires once")
        throttler.tick(id, action: record("dropped", droppedShouldNotRun))
        throttler.tick(id, action: record("latest", trailingFired))

        await fulfillment(of: [trailingFired], timeout: 1)
        await fulfillment(of: [droppedShouldNotRun], timeout: 0.2)

        fired.tags.withLock { XCTAssertEqual($0, ["first", "latest"]) }
    }

    // `commit` flushes the final value immediately and cancels any deferred trailing tick,
    // so the last drag value is never lost and the superseded one never runs.
    func test_commit_flushesFinalValueAndDropsDeferred() async {
        let now = Mutex(Date(timeIntervalSince1970: 1000))
        let throttler = SliderThrottler(interval: 0.2, clock: { now.withLock { $0 } })
        let id = UUID()

        let firstFired = expectation(description: "first tick fires immediately")
        throttler.tick(id, action: record("first", firstFired))
        await fulfillment(of: [firstFired], timeout: 1)

        // Deferred ticks that commit must supersede (they must never run).
        let deferredShouldNotRun = expectation(description: "deferred ticks dropped by commit")
        deferredShouldNotRun.isInverted = true
        throttler.tick(id, action: record("deferredA", deferredShouldNotRun))
        throttler.tick(id, action: record("deferredB", deferredShouldNotRun))

        let committed = expectation(description: "commit flushes final value")
        throttler.commit(id, action: record("commit", committed))
        await fulfillment(of: [committed], timeout: 1)
        // Past the 0.2 interval — confirms the deferred trailing fire was cancelled.
        await fulfillment(of: [deferredShouldNotRun], timeout: 0.4)

        fired.tags.withLock { XCTAssertEqual($0, ["first", "commit"]) }
    }

    // Separate ids keep separate windows — one slider's throttle must not gate another's.
    func test_tick_perIdWindowsAreIndependent() async {
        let now = Mutex(Date(timeIntervalSince1970: 1000))
        let throttler = SliderThrottler(interval: 0.2, clock: { now.withLock { $0 } })

        let firstFired = expectation(description: "slider A fires")
        let secondFired = expectation(description: "slider B fires")
        throttler.tick(UUID(), action: record("A", firstFired))
        throttler.tick(UUID(), action: record("B", secondFired))

        await fulfillment(of: [firstFired, secondFired], timeout: 1)
        fired.tags.withLock { XCTAssertEqual($0.sorted(), ["A", "B"]) }
    }

    // A run that never completes in time must not wedge the per-id serial chain: once it
    // overruns `runTimeout` it is abandoned (cancelled, not awaited), so a later submission on
    // the same id still runs. Before the timeout fix, the stalled run's task was awaited forever
    // and every subsequent run on that id was blocked permanently ("worked a few times, then
    // stopped"). The stalled run here ignores cancellation — an inner detached sleep does not
    // inherit the cancel — to mimic a process whose pipe EOF is deferred (e.g. a backgrounded
    // grandchild holding the write end), proving the chain advances even then.
    func test_stalledRun_doesNotBlockSubsequentRunsOnSameId() async {
        let throttler = SliderThrottler(
            interval: 0.2,
            runTimeout: 0.05,                                 // 50ms run budget
            clock: { Date(timeIntervalSince1970: 1000) }
        )
        let id = UUID()
        let log = fired

        // Submitted first: does not finish for 2s even when cancelled.
        throttler.commit(id) {
            await Task.detached { try? await Task.sleep(for: .seconds(2)) }.value
            log.tags.withLock { $0.append("stalled") }
        }

        // Submitted second: must still run, well before the 2s stall would have ended.
        let fastDone = expectation(description: "later run executes despite the stalled run")
        throttler.commit(id, action: record("fast", fastDone))

        await fulfillment(of: [fastDone], timeout: 1)
        // The stalled run was abandoned at the deadline, so only the fast run has recorded.
        fired.tags.withLock { XCTAssertEqual($0, ["fast"]) }
    }

    // Runs are conflated per id: at most one waits behind the active run, and a newer submission
    // replaces the waiting one. So submissions that pile up while a run is busy collapse to just
    // the latest — intermediates are dropped, never run. This bounds how many runs can pile up
    // behind a slow/stuck run (and how many can leak in the abandoned-run case).
    func test_runs_coalesceQueuedToLatestWhileBusy() async {
        let throttler = SliderThrottler(interval: 0.2, clock: { Date(timeIntervalSince1970: 1000) })
        let id = UUID()
        let log = fired

        let firstStarted = expectation(description: "first (slow) run started")
        let firstDone = expectation(description: "first run completes")
        let latestDone = expectation(description: "latest queued run completes")
        let middleDropped = expectation(description: "intermediate queued run is dropped")
        middleDropped.isInverted = true

        // First run is slow and already in flight before the next two are queued, so they land
        // behind it; the third supersedes the second while the first is still running.
        throttler.commit(id) {
            firstStarted.fulfill()
            try? await Task.sleep(for: .milliseconds(100))
            log.tags.withLock { $0.append("first") }
            firstDone.fulfill()
        }
        await fulfillment(of: [firstStarted], timeout: 1)
        throttler.commit(id, action: record("middle", middleDropped))
        throttler.commit(id, action: record("latest", latestDone))

        await fulfillment(of: [firstDone, latestDone], timeout: 2)
        await fulfillment(of: [middleDropped], timeout: 0.3)
        // Only the active run and the newest queued run execute; the intermediate is coalesced away.
        fired.tags.withLock { XCTAssertEqual($0, ["first", "latest"]) }
    }
}
