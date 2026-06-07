import Foundation
import SwiftData

/// Per-type table for slider entries — the command line (with `<VALUE>`), the numeric
/// bounds/step, and the last committed value. Mirrors `CommandEntryModel`'s shape.
@Model
final class SliderEntryModel {
    var commandLine: String        // required — shell command line containing `<VALUE>`
    var minValue: Double
    var maxValue: Double
    var step: Double
    var currentValue: Double

    var entry: EntryModel?         // inverse of EntryModel.slider (cascade parent)

    init(commandLine: String, minValue: Double, maxValue: Double, step: Double, currentValue: Double) {
        self.commandLine = commandLine
        self.minValue = minValue
        self.maxValue = maxValue
        self.step = step
        self.currentValue = currentValue
    }
}
