import Foundation

/// The global "Command Output" setting: how many trailing lines of a background
/// command's captured output to retain in the persisted run record (and the
/// completion notification's result). The in-session live hover window is bounded
/// separately by a fixed character budget, independent of this line count. Output
/// beyond this scrolls out — newest lines are kept. Construction
/// clamps the value into a sane range, so an out-of-range stored or entered value
/// can never take effect.
struct CommandOutputPreference: Equatable, Sendable {
    static let minBufferLines = 100
    static let maxBufferLines = 100_000

    let bufferLines: Int

    init(bufferLines: Int) {
        self.bufferLines = min(max(bufferLines, Self.minBufferLines), Self.maxBufferLines)
    }

    static let `default` = CommandOutputPreference(bufferLines: 1000)
}
