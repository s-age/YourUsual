import Foundation
import Observation

/// Slider target — owns the command line (which must carry a `<VALUE>` placeholder)
/// and the numeric bounds (min / max / step / initial value). Validation (non-empty,
/// contains `<VALUE>`, min < max, step > 0) lives in the Request, mirroring the other
/// child forms; this only collects fields and builds the payload. Menu-bar visibility
/// is *not* exposed — the Domain forces a slider hidden from the menu bar.
@Observable
@MainActor
final class SliderEntryFormViewModel {
    var commandLine = ""
    var minValue: Double = 0
    var maxValue: Double = 100
    var step: Double = 1
    var currentValue: Double = 0

    /// Prefill from an existing slider entry when editing.
    func load(_ slider: SliderPayload) {
        commandLine = slider.commandLine
        minValue = slider.minValue
        maxValue = slider.maxValue
        step = slider.step
        currentValue = slider.currentValue
    }

    func buildKind() -> EntryKindPayload {
        .slider(SliderPayload(
            commandLine: commandLine,
            minValue: minValue,
            maxValue: maxValue,
            step: step,
            currentValue: currentValue
        ))
    }
}
