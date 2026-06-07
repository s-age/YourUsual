import Foundation

/// A registered slider: a horizontal control that substitutes its current value into a
/// shell command and runs it fire-and-forget. `commandLine` carries the `<VALUE>`
/// placeholder (see `SliderValueToken`), replaced with the numeric value at run time —
/// the same shape as a command entry's `<WORKING_DIRECTORY>` sentinel. Always runs in the
/// background and surfaces neither a notification nor run history. `currentValue` is the
/// last committed position, persisted so the slider restores where the user left it.
struct SliderEntry: Equatable, Sendable {
    var commandLine: String   // must contain `<VALUE>`; validated in the Request
    var minValue: Double
    var maxValue: Double
    var step: Double          // > 0
    var currentValue: Double  // clamped to [minValue, maxValue]

    init(commandLine: String, minValue: Double, maxValue: Double, step: Double, currentValue: Double) {
        self.commandLine = commandLine
        self.minValue = minValue
        self.maxValue = maxValue
        self.step = step
        self.currentValue = currentValue
    }

    /// Returns a copy with `currentValue` replaced (clamped to bounds). Pure immutable
    /// update — used by the gerund transform when persisting a new position.
    func updating(currentValue value: Double) -> SliderEntry {
        var copy = self
        copy.currentValue = min(max(value, minValue), maxValue)
        return copy
    }
}
