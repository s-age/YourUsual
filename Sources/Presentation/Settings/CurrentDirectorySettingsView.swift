import SwiftUI
import UniformTypeIdentifiers

/// Detail pane for the "Current Directory" sidebar item: choose the global directory
/// that commands run in (and that is exported to every command as
/// `YOUR_USUAL_CURRENT_DIRECTORY`). Persisted to a state file shared with the
/// `your-usual cd <path>` CLI, so it survives relaunch; resolves to the home directory
/// when cleared or when the chosen folder no longer exists.
struct CurrentDirectorySettingsView: View {
    @Bindable var viewModel: CurrentDirectorySettingsViewModel
    /// Pure presentation state for the folder-browse `.fileImporter` sheet.
    @State private var isImporting = false

    init(viewModel: CurrentDirectorySettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Form {
            if viewModel.settings != nil {
                Section("Current Directory") {
                    LabeledContent("Directory", value: viewModel.displayPath)
                    HStack {
                        Spacer()
                        Button("Choose Folder…") { isImporting = true }
                        Button("Reset to Home") { viewModel.resetToHome() }
                    }
                }
                Section {
                    Text("Commands run here by default (commands whose working directory is "
                        + "“\(WorkingDirectoryToken.current)”), and every command can "
                        + "reference it as $YOUR_USUAL_CURRENT_DIRECTORY. Persisted across "
                        + "launches; you can also set it from a terminal with `your-usual cd`.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Current Directory")
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder]) { result in
            viewModel.handleImport(result)
        }
        // `load()` is synchronous (a small file read), so `.onAppear` is the honest hook.
        .onAppear { viewModel.load() }
        .actionErrorAlert($viewModel.actionError)
    }
}
