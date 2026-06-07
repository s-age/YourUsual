import SwiftUI

/// Detail pane for the "Command Output" sidebar item: the scroll-buffer size that
/// bounds how many trailing lines of a background command's output are retained in
/// the persisted run record. (The live hover window is capped separately by a fixed
/// character budget.) Older lines scroll out.
struct CommandOutputSettingsView: View {
    @Bindable var viewModel: CommandOutputSettingsViewModel

    init(viewModel: CommandOutputSettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Form {
            if let settings = viewModel.settings {
                Section("Command Output") {
                    LabeledContent("Scroll buffer (lines)") {
                        TextField("", text: $viewModel.bufferLinesText)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .onSubmit { viewModel.commit() }
                    }
                    Text("Background commands keep only their most recent "
                        + "\(settings.bufferLines) lines of output; older lines scroll out. "
                        + "Allowed range \(settings.minBufferLines)–\(settings.maxBufferLines).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Command Output")
        // `load()` is synchronous (UserDefaults read), so `.onAppear` is the honest
        // hook — `.task` would imply awaited, cancellable lifecycle work.
        .onAppear { viewModel.load() }
        // Commit a pending edit when leaving the pane (e.g. switching sidebar items),
        // so a typed-but-not-submitted value is not lost. `commit()` no-ops when the
        // value is unchanged.
        .onDisappear { viewModel.commit() }
        .actionErrorAlert($viewModel.actionError)
    }
}
