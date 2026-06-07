import Foundation

/// Accumulates streamed stdout/stderr as a **scroll buffer**: it retains only the
/// last `maxLines` lines (the user's "Command Output" buffer setting), dropping older
/// lines as new ones arrive. This keeps the persisted history record bounded so a
/// runaway command (`yes`, an accidental `tail -f`, a huge build log)
/// cannot grow this process's memory without bound. Live output still reaches the UI
/// in full via the stream; only the retained copy is bounded. How much of a run to keep
/// is a retention policy (a domain decision), so this value type lives in `Domain/Entities`.
///
/// A hard total-byte ceiling (`maxRetainedBytes`) backstops the line cap so a
/// newline-free runaway (`cat /dev/urandom`) — which would otherwise be a single
/// unbounded "line" — can't defeat it; an over-long single line is also flushed once
/// it exceeds `maxPendingBytes`.
///
/// Eviction is **amortized O(1)**: the oldest line is dropped by advancing a `head`
/// index (not `Array.removeFirst`, which is O(n)), and the dead prefix is reclaimed in
/// one compaction pass only after it grows to dominate the backing array — so a runaway
/// command stays linear in total work.
struct BoundedLineBuffer: Sendable {
    /// Hard ceiling on retained bytes regardless of line count (memory backstop).
    private static let maxRetainedBytes = 8 << 20    // 8 MiB
    /// A single un-newlined line is flushed (truncated) once it reaches this size.
    private static let maxPendingBytes = 1 << 20     // 1 MiB
    /// Compact the dead prefix only past this many evicted slots (avoids churn for small buffers).
    private static let compactionFloor = 1024

    private let maxLines: Int
    private var lines: [String] = []   // retained lines; the live range is `lines[head...]`
    private var head = 0               // index of the oldest live line (evicted lines sit before it)
    private var pending = ""           // current partial line (no newline seen yet)
    private var retainedBytes = 0
    private var droppedOldLines = false

    init(maxLines: Int) {
        self.maxLines = max(maxLines, 1)
    }

    private var liveCount: Int { lines.count - head }

    mutating func append(_ chunk: String) {
        // `omittingEmptySubsequences: false` preserves blank lines; the final element
        // is the new partial line (empty when the chunk ended on a newline).
        let parts = (pending + chunk).split(separator: "\n", omittingEmptySubsequences: false)
        for part in parts.dropLast() { pushLine(String(part)) }
        pending = String(parts.last ?? "")
        if pending.utf8.count > Self.maxPendingBytes {
            // No newline in sight and the line is huge — flush a truncated copy so a
            // newline-free runaway can't grow `pending` without bound, then reset it.
            pushLine(String(decoding: pending.utf8.prefix(Self.maxPendingBytes), as: UTF8.self)
                + " … (line truncated)")
            pending = ""
        }
    }

    private mutating func pushLine(_ line: String) {
        lines.append(line)
        retainedBytes += line.utf8.count + 1   // +1 for the joining newline
        while (liveCount > maxLines || retainedBytes > Self.maxRetainedBytes) && liveCount > 0 {
            retainedBytes -= lines[head].utf8.count + 1
            lines[head] = ""                   // release the evicted string eagerly
            head += 1
            droppedOldLines = true
        }
        // Reclaim the dead prefix only once it dominates the array; this O(n) pass then
        // runs at most every ~`head` pushes, keeping `pushLine` amortized O(1).
        if head > Self.compactionFloor && head >= liveCount {
            lines.removeFirst(head)
            head = 0
        }
    }

    /// The retained output, with a leading marker when older lines were dropped.
    var text: String {
        var all = Array(lines[head...])
        if !pending.isEmpty { all.append(pending) }
        let body = all.joined(separator: "\n")
        guard droppedOldLines else { return body }
        return "… (earlier output dropped; keeping the last \(maxLines) lines)\n" + body
    }
}
