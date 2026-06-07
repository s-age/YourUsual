import SwiftUI
import UniformTypeIdentifiers

/// Form rows for the Command target. Designed to be embedded inside the parent
/// `Form`; its top-level views become individual form rows.
struct CommandEntryFormView: View {
    @Bindable var viewModel: CommandEntryFormViewModel
    /// Pure presentation state for the working-directory `.fileImporter` sheet —
    /// kept in the View, not the VM, since "is the picker showing" is not VM state.
    @State private var isImportingWorkingDirectory = false

    init(viewModel: CommandEntryFormViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        TextField("Command", text: $viewModel.commandLine)

        Text("Runs through your login shell with your full user privileges. "
            + "Register only commands you trust — you run them at your own risk.")
            .font(.caption)
            .foregroundStyle(.secondary)

        TextField("Working directory", text: $viewModel.workingDirectory)

        // Buttons sit on their own row below the path field so a long path isn't
        // crowded onto the same line. Right-aligned to read as actions on the field.
        HStack {
            Spacer()
            Button("Browse…") { isImportingWorkingDirectory = true }
            Button("Use Current") { viewModel.useCurrentDirectory() }
                .help("Run in the app's current directory (\(WorkingDirectoryToken.current))")
        }
        .fileImporter(
            isPresented: $isImportingWorkingDirectory,
            allowedContentTypes: [.folder]
        ) { result in
            viewModel.handleWorkingDirectoryImport(result)
        }
        .fileDialogDefaultDirectory(viewModel.browseDefaultDirectory)

        if viewModel.isUsingCurrentDirectory {
            Text("Runs in the app's current directory (set in Settings or via "
                + "`your-usual cd`), exported as $YOUR_USUAL_CURRENT_DIRECTORY.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Picker("Action", selection: $viewModel.handlerKind) {
            ForEach(viewModel.availableHandlerKinds, id: \.self) { kind in
                Text(label(for: kind)).tag(kind)
            }
        }
        if viewModel.handlerKind == .terminal {
            Text("Uses the Terminal App setting (app + launch mode).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func label(for kind: CommandEntryFormViewModel.HandlerKind) -> String {
        switch kind {
        case .background: return "Run in background"
        case .terminal:   return "Run in terminal"
        }
    }
}
