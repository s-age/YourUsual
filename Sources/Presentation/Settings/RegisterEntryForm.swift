import SwiftUI

struct RegisterEntryForm: View {
    @Bindable var formViewModel: RegisterEntryFormViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRecoveredSave = false
    @FocusState private var nameFieldFocused: Bool

    init(formViewModel: RegisterEntryFormViewModel) {
        self.formViewModel = formViewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Grouped style top-aligns the fields and lets the AppleScript editor
            // expand, so every type starts from the same place regardless of how
            // many fields it has. The form scrolls above the pinned footer.
            Form {
                Section {
                    TextField("Name", text: $formViewModel.name)
                        .focused($nameFieldFocused)

                    Picker("Type", selection: $formViewModel.entryKind) {
                        Text("File / Directory").tag(RegisterEntryFormViewModel.EntryKind.browse)
                        Text("Command").tag(RegisterEntryFormViewModel.EntryKind.command)
                        Text("AppleScript").tag(RegisterEntryFormViewModel.EntryKind.appleScript)
                        Text("Slider").tag(RegisterEntryFormViewModel.EntryKind.slider)
                    }

                    // Only when editing, and never for a slider: the register path always
                    // creates a visible entry, and the Domain forces a slider hidden from the
                    // menu bar regardless of this flag, so don't offer a toggle that does nothing.
                    if formViewModel.isEditing && formViewModel.entryKind != .slider {
                        Toggle("Show in menu bar", isOn: $formViewModel.showsInMenuBar)
                    }
                }

                Section {
                    typeFields
                }
            }
            .formStyle(.grouped)

            footer
        }
        .navigationTitle(formViewModel.title)
        .task { nameFieldFocused = true }
    }

    /// Pinned action bar: Save stays bottom-right so its position never shifts as
    /// the form's field count changes between types. Validation sits to its left.
    private var footer: some View {
        HStack(spacing: 12) {
            if let message = formViewModel.validationMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button("Save") {
                // Saving a recovered placeholder overwrites the original (lost)
                // definition permanently — confirm before committing that.
                if formViewModel.isEditingRecovered {
                    confirmingRecoveredSave = true
                } else {
                    save()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(formViewModel.isSaving || !formViewModel.isDirty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .confirmationDialog(
            "Overwrite the original item?",
            isPresented: $confirmingRecoveredSave,
            titleVisibility: .visible
        ) {
            Button("Overwrite", role: .destructive) { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This item couldn’t be loaded, so it’s shown as a placeholder. Saving "
                 + "replaces the original definition with what’s in this form. This can’t be undone.")
        }
    }

    private func save() {
        Task {
            if await formViewModel.submit() {
                dismiss()
            }
        }
    }

    /// Each target kind renders its own self-contained subview, driven by its own
    /// child ViewModel.
    @ViewBuilder
    private var typeFields: some View {
        switch formViewModel.entryKind {
        case .browse:
            BrowseEntryFormView(viewModel: formViewModel.browseForm)
        case .command:
            CommandEntryFormView(viewModel: formViewModel.commandForm)
        case .appleScript:
            AppleScriptEntryFormView(viewModel: formViewModel.applescriptForm)
        case .slider:
            SliderEntryFormView(viewModel: formViewModel.sliderForm)
        }
    }
}
