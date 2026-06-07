import SwiftUI
import UniformTypeIdentifiers

/// Detail pane for the "Terminal App" sidebar item: pick which terminal runs
/// commands (Terminal.app / iTerm2 / a browsed app) and how (new window / tab /
/// reuse). The available launch modes follow the selected app's capability.
struct TerminalSettingsView: View {
    @Bindable var viewModel: TerminalSettingsViewModel
    /// Pure presentation state for the app-browse `.fileImporter` sheet — kept in
    /// the View, not the VM, since "is the picker showing" is not VM state.
    @State private var isImporting = false

    init(viewModel: TerminalSettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Form {
            if let settings = viewModel.settings {
                Section("Terminal App") {
                    Picker("Application", selection: $viewModel.selectedAppID) {
                        ForEach(settings.available) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Choose Application…") { isImporting = true }
                    }
                }

                Section("Run Command") {
                    Picker("Mode", selection: $viewModel.selectedMode) {
                        ForEach(settings.selected.supportedModes) { mode in
                            Text(mode.displayLabel).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Terminal App")
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.application]
        ) { result in
            viewModel.handleImport(result)
        }
        // `load()` is synchronous (UserDefaults read), so `.onAppear` is the honest
        // hook — `.task` would imply awaited, cancellable lifecycle work.
        .onAppear { viewModel.load() }
        // Surface a failed read/write/import instead of silently swallowing it
        // (and, for a write, blanking the pane into a permanent spinner).
        .actionErrorAlert($viewModel.actionError)
    }
}
