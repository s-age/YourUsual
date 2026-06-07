import SwiftUI

/// Source-list sidebar of categories for Settings → "Shortcuts", mirroring System
/// Settings. Selection drives the cards shown in the detail pane; the global Terminal
/// App / Command Output panes sit above the category list. A "+" bar pinned to the
/// bottom adds a category inline; right-click deletes one along with its entries.
struct CategorySidebarView: View {
    @Bindable var viewModel: SettingsViewModel

    /// The category row currently under a dragged entry, for drop highlighting.
    @State private var dropTargetCategoryID: UUID?
    @State private var pendingDeletion: CategoryResponse?
    @FocusState private var addFieldFocused: Bool
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        List(selection: $viewModel.selection) {
            Section {
                ForEach(SettingsSection.globalPanes) { pane in
                    Label(pane.title, systemImage: pane.icon)
                        .tag(pane.section)
                }
            }
            Section("Categories") {
                ForEach(viewModel.categories) { category in
                    HStack {
                        if viewModel.renamingCategoryID == category.id {
                            // Inline rename: swap the label for a seeded field, mirroring
                            // the "New Category" add field below.
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            TextField("Category Name", text: $viewModel.renameCategoryName)
                                .textFieldStyle(.plain)
                                .focused($renameFieldFocused)
                                .onSubmit { Task { await viewModel.commitRenameCategory() } }
                                .onExitCommand { viewModel.cancelRenameCategory() }
                                .onAppear { renameFieldFocused = true }
                        } else {
                            Label(category.name, systemImage: "folder")
                            if category.isHiddenFromMenuBar {
                                Spacer()
                                // Muted marker so a menu-bar-hidden category is recognizable
                                // in Settings (where it still appears).
                                Image(systemName: "eye.slash")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                    .help("Hidden from the menu bar")
                            }
                        }
                    }
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(dropTargetCategoryID == category.id
                                      ? Color.accentColor.opacity(0.25) : .clear)
                        )
                        .tag(SettingsSection.category(category.id))
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                viewModel.beginRenameCategory(category)
                            }
                            Button(
                                category.isHiddenFromMenuBar ? "Show in menu bar" : "Hide from menu bar",
                                systemImage: category.isHiddenFromMenuBar ? "eye" : "eye.slash"
                            ) {
                                Task { await viewModel.toggleCategoryVisibility(category) }
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                pendingDeletion = category
                            }
                        }
                        // Accept an entry dragged from the detail list; the payload
                        // is the entry id (uuidString) emitted by the row's `.onDrag`.
                        .dropDestination(for: String.self) { ids, _ in
                            guard let entryID = ids.compactMap(UUID.init(uuidString:)).first
                            else { return false }
                            Task { await viewModel.moveEntry(entryID, to: category.id) }
                            return true
                        } isTargeted: { targeted in
                            dropTargetCategoryID = targeted ? category.id : nil
                        }
                }
                if viewModel.isAddingCategory {
                    TextField("New Category", text: $viewModel.newCategoryName)
                        .focused($addFieldFocused)
                        .onSubmit { Task { await viewModel.commitAddCategory() } }
                        .onExitCommand { viewModel.cancelAddCategory() }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            CategorySidebarToolbar(
                viewModel: viewModel,
                addCategoryFieldFocused: $addFieldFocused
            )
        }
        .confirmationDialog(
            "Delete Category",
            isPresented: deletionPresented,
            presenting: pendingDeletion
        ) { category in
            Button("Delete “\(category.name)” and its items", role: .destructive) {
                Task { await viewModel.removeCategory(category) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { category in
            Text("Deleting “\(category.name)” also deletes every item it contains. This can’t be undone.")
        }
    }

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }
}
