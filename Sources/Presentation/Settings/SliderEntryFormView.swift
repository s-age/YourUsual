import SwiftUI

/// Form rows for the Slider target. Designed to be embedded inside the parent
/// `Form`; its top-level views become individual form rows.
struct SliderEntryFormView: View {
    @Bindable var viewModel: SliderEntryFormViewModel

    init(viewModel: SliderEntryFormViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        TextField("Command", text: $viewModel.commandLine)

        Text("Include \(SliderValueToken.placeholder) where the slider's value should go "
            + "(e.g. set volume output volume \(SliderValueToken.placeholder)). Runs through "
            + "your login shell with your full user privileges — register only commands you trust.")
            .font(.caption)
            .foregroundStyle(.secondary)

        TextField("Minimum", value: $viewModel.minValue, format: .number)
        TextField("Maximum", value: $viewModel.maxValue, format: .number)
        TextField("Step", value: $viewModel.step, format: .number)
        TextField("Initial value", value: $viewModel.currentValue, format: .number)
    }
}
