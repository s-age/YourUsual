import SwiftUI

/// Bottom bar of the category sidebar: "Add Category" on the left, plus up/down
/// buttons that reorder the currently-selected category. Buttons are used
/// instead of drag-to-reorder because the sidebar's selection consumes row drags.
struct CategorySidebarToolbar: View {
    @Bindable var viewModel: SettingsViewModel
    /// The sidebar's add-field focus, owned by `SettingsRootView`; the "Add
    /// Category" button moves focus into the inline editor.
    var addCategoryFieldFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 4) {
            Button("Add Category", systemImage: "plus") {
                viewModel.beginAddCategory()
                addCategoryFieldFocused.wrappedValue = true
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Move Up", systemImage: "chevron.up") {
                Task { await viewModel.moveSelectedCategory(by: -1) }
            }
            .labelStyle(.iconOnly)
            .help("Move category up")
            .disabled(!viewModel.canMoveSelectedCategoryUp)

            Button("Move Down", systemImage: "chevron.down") {
                Task { await viewModel.moveSelectedCategory(by: 1) }
            }
            .labelStyle(.iconOnly)
            .help("Move category down")
            .disabled(!viewModel.canMoveSelectedCategoryDown)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
