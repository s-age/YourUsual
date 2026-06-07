import SwiftUI

/// Source-list sidebar of launcher pads for Settings → "Pads", mirroring the category
/// sidebar: selection drives the detail editor; the bottom bar adds a pad inline and
/// reorders the selection; right-click deletes a pad (and its cells). Owns the shared
/// `PadViewModel` so edits here show live in the launcher panel.
struct PadsSidebarView: View {
    @Bindable var viewModel: PadViewModel
    /// Settings-owned selection — separate from the launcher panel's displayed pad.
    @Binding var selectedID: UUID?
    /// The global pane currently shown in the Pads detail (highlights its row), or nil.
    let activeGlobalPane: SettingsSection?
    /// Opens a global pane (Terminal/Output/Directory) in the Pads detail, staying in Pads mode.
    let selectGlobalPane: (SettingsSection) -> Void

    @State private var isAddingPad = false
    @State private var newPadName = ""
    @State private var pendingDeletion: PadLayoutResponse?
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        List(selection: $selectedID) {
            // The app-global panes stay pinned at the top across both tabs. They're
            // buttons (not selectable rows) because the list's selection is a pad id;
            // tapping one swaps the detail to that pane without leaving the Pads tab.
            Section {
                ForEach(SettingsSection.globalPanes) { pane in
                    Button { selectGlobalPane(pane.section) } label: {
                        Label(pane.title, systemImage: pane.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(activeGlobalPane == pane.section
                        ? Color.accentColor.opacity(0.15) : nil)
                }
            }
            Section("Pads") {
                ForEach(viewModel.response.layouts, id: \.id) { layout in
                    Label(layout.name, systemImage: "rectangle.grid.2x2")
                        .padding(.vertical, 2)
                        .tag(layout.id)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                pendingDeletion = layout
                            }
                        }
                }
                if isAddingPad {
                    TextField("New Pad", text: $newPadName)
                        .focused($addFieldFocused)
                        .onSubmit { Task { await commitAdd() } }
                        .onExitCommand { cancelAdd() }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { toolbar }
        .confirmationDialog(
            "Delete Pad",
            isPresented: deletionPresented,
            presenting: pendingDeletion
        ) { layout in
            Button("Delete “\(layout.name)” and its cells", role: .destructive) {
                Task { await viewModel.deleteLayout(id: layout.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { layout in
            Text("Deleting “\(layout.name)” also deletes every cell it contains. This can’t be undone.")
        }
    }

    /// Bottom bar: "Add Pad" plus up/down buttons that reorder the selected pad —
    /// same shape as `CategorySidebarToolbar`.
    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 4) {
            Button("Add Pad", systemImage: "plus") {
                beginAdd()
                addFieldFocused = true
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Move Up", systemImage: "chevron.up") {
                Task { await viewModel.moveLayout(id: selectedID, by: -1) }
            }
            .labelStyle(.iconOnly)
            .help("Move pad up")
            .disabled(!viewModel.canMoveLayout(id: selectedID, by: -1))

            Button("Move Down", systemImage: "chevron.down") {
                Task { await viewModel.moveLayout(id: selectedID, by: 1) }
            }
            .labelStyle(.iconOnly)
            .help("Move pad down")
            .disabled(!viewModel.canMoveLayout(id: selectedID, by: 1))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Helpers

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private func beginAdd() {
        newPadName = ""
        isAddingPad = true
    }

    private func cancelAdd() {
        isAddingPad = false
        newPadName = ""
    }

    /// Commits the inline new-pad name with default 4×3 dimensions (tweaked afterward in
    /// the editor), mirroring the category inline-add flow. Selects the new pad in the
    /// *Settings* list only — the launcher panel's displayed pad is left unchanged.
    private func commitAdd() async {
        let name = newPadName.trimmingCharacters(in: .whitespacesAndNewlines)
        isAddingPad = false
        newPadName = ""
        guard !name.isEmpty else { return }
        if let id = await viewModel.registerLayout(name: name, columns: 4, rows: 3) {
            selectedID = id
        }
    }
}
