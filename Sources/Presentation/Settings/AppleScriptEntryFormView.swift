import SwiftUI

/// Form rows for the AppleScript target. Designed to be embedded inside the
/// parent `Form`.
struct AppleScriptEntryFormView: View {
    @Bindable var viewModel: AppleScriptEntryFormViewModel

    init(viewModel: AppleScriptEntryFormViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        TextEditor(text: $viewModel.source)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 120)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.separator, lineWidth: 1)
            )

        Text("Runs with your full user privileges and can automate and control "
            + "your Mac. Register only scripts you trust — you run them at your own risk.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
