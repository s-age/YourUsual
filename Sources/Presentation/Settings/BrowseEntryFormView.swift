import SwiftUI
import UniformTypeIdentifiers

/// Form rows for the browse (File / Directory) target. Designed to be embedded inside
/// the parent `Form`; its top-level views become individual form rows.
struct BrowseEntryFormView: View {
    @Bindable var viewModel: BrowseEntryFormViewModel
    /// Pure presentation state for the two `.fileImporter` sheets — kept in the
    /// View, not the VM, since "is the picker showing" is not domain/VM state.
    @State private var isImportingPath = false
    @State private var isImportingApp = false

    init(viewModel: BrowseEntryFormViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        HStack {
            TextField("Path", text: $viewModel.path)
            Button("Browse…") { isImportingPath = true }
        }
        .fileImporter(
            isPresented: $isImportingPath,
            allowedContentTypes: [.item, .folder]
        ) { result in
            viewModel.handlePathImport(result)
        }
        .fileDialogDefaultDirectory(viewModel.pathBrowseDefaultDirectory)

        HStack {
            TextField("App bundle identifier", text: $viewModel.appBundleIdentifier)
            Button("Open with…") { isImportingApp = true }
        }
        .fileImporter(
            isPresented: $isImportingApp,
            allowedContentTypes: [.applicationBundle]
        ) { result in
            viewModel.handleAppImport(result)
        }
        .fileDialogDefaultDirectory(URL(fileURLWithPath: "/Applications"))
    }
}
