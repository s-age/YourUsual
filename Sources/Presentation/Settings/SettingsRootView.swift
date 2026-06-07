import SwiftUI

struct SettingsRootView: View {
    @Bindable var viewModel: SettingsViewModel
    /// Shared launcher-pad VM (same instance the panel uses) — drives the "Pads" tab's
    /// sidebar list and detail editor, so edits here show live in the panel.
    @Bindable var padViewModel: PadViewModel

    private let terminalViewModel: TerminalSettingsViewModel
    private let commandOutputViewModel: CommandOutputSettingsViewModel
    private let currentDirectoryViewModel: CurrentDirectorySettingsViewModel
    private let makeFormViewModel: @MainActor @Sendable (SavedEntryResponse?, UUID?) -> RegisterEntryFormViewModel
    private let makeHistoryViewModel: @MainActor @Sendable (SavedEntryResponse?) -> RunHistoryViewModel

    @State private var historySelection: HistorySelection?
    @State private var entryPendingDeletion: SavedEntryResponse?
    /// The entry row currently under a dragged entry, for reorder insertion highlight.
    @State private var dropTargetEntryID: UUID?

    init(
        viewModel: SettingsViewModel,
        padViewModel: PadViewModel,
        terminalViewModel: TerminalSettingsViewModel,
        commandOutputViewModel: CommandOutputSettingsViewModel,
        currentDirectoryViewModel: CurrentDirectorySettingsViewModel,
        makeFormViewModel: @escaping @MainActor @Sendable (SavedEntryResponse?, UUID?) -> RegisterEntryFormViewModel,
        makeHistoryViewModel: @escaping @MainActor @Sendable (SavedEntryResponse?) -> RunHistoryViewModel
    ) {
        self.viewModel = viewModel
        self.padViewModel = padViewModel
        self.terminalViewModel = terminalViewModel
        self.commandOutputViewModel = commandOutputViewModel
        self.currentDirectoryViewModel = currentDirectoryViewModel
        self.makeFormViewModel = makeFormViewModel
        self.makeHistoryViewModel = makeHistoryViewModel
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 215, max: 280)
        } detail: {
            VStack(spacing: 0) {
                tabBar
                Divider()
                // Fill the remaining height so the tab bar pins to the top; an empty
                // ContentUnavailableView still centers within this lower region.
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationSplitViewColumnWidth(min: 360, ideal: 480)
        }
        .toolbar {
            // History spans both tabs: run results are "execution output" the user
            // should be able to review/clear at any time, regardless of the active
            // tab. Entry-add stays Shortcuts-only — Pads manages its own list inline
            // (sidebar bottom bar) and edits in the detail pane.
            ToolbarItem {
                Button("All History", systemImage: "clock.arrow.circlepath") {
                    historySelection = .all
                }
            }
            if viewModel.tab == .shortcuts {
                ToolbarItem {
                    Button("Add", systemImage: "plus") { viewModel.beginAdd() }
                        .disabled(!viewModel.canAddEntry)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 380)
        .sheet(item: $historySelection) { selection in
            NavigationStack {
                RunHistoryView(viewModel: makeHistoryViewModel(selection.entry))
            }
        }
        // Switching the sidebar selection pops any open form back to the list,
        // so a half-edited form never lingers under a different category.
        .onChange(of: viewModel.selection) { viewModel.formPath = [] }
        // Picking a pad (in the Pads tab) drops any pinned-global-pane override so
        // the editor shows. `showGlobalPaneInPads` sets the id to nil, which never
        // trips this (guarded on non-nil).
        .onChange(of: viewModel.selectedLayoutID) { _, newID in
            if newID != nil { viewModel.padsGlobalPane = nil }
        }
        .task { await viewModel.load() }
        .task { await padViewModel.load() }
        // Surface a failed mutation (delete/move/reorder/add) instead of letting
        // it revert silently on the next reload. Pad mutations surface their own.
        .actionErrorAlert($viewModel.actionError)
        .actionErrorAlert($padViewModel.actionError)
    }

    /// Segmented Shortcuts/Pads switch above the detail pane. Drives both the
    /// sidebar content and the detail body.
    @ViewBuilder
    private var tabBar: some View {
        Picker("Mode", selection: $viewModel.tab) {
            Text("Shortcuts").tag(SettingsTab.shortcuts)
            Text("Pads").tag(SettingsTab.pads)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .padding(8)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var sidebar: some View {
        switch viewModel.tab {
        case .shortcuts: categorySidebar
        case .pads: padsSidebar
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch viewModel.tab {
        case .shortcuts: detailColumn
        case .pads: padsDetail
        }
    }

    // MARK: - Sidebars

    private var categorySidebar: some View {
        CategorySidebarView(viewModel: viewModel)
    }

    private var padsSidebar: some View {
        PadsSidebarView(
            viewModel: padViewModel,
            selectedID: $viewModel.selectedLayoutID,
            activeGlobalPane: viewModel.padsGlobalPane,
            selectGlobalPane: { viewModel.showGlobalPaneInPads($0) }
        )
    }

    /// Editor for the Settings-selected pad, or an empty state when none is selected.
    /// Resolved from the Settings selection (not the panel's), and `.id` re-seeds
    /// `PadEditorView`'s form state when the selection changes.
    @ViewBuilder
    private var padsDetail: some View {
        // A pinned global row was tapped: show that pane without leaving Pads mode.
        if let pane = viewModel.padsGlobalPane {
            globalPane(pane)
        }
        // `viewModel` is the SettingsViewModel selection (the Pads-tab editor target),
        // distinct from each launcher panel's pinned `layoutID` (the pad it displays).
        else if let layout = padViewModel.response.layouts.first(where: { $0.id == viewModel.selectedLayoutID }) {
            PadEditorView(viewModel: padViewModel, layout: layout)
                .id(layout.id)
        } else {
            ContentUnavailableView {
                Label("No Pad Selected", systemImage: "rectangle.grid.2x2")
            } description: {
                Text("Select a pad, or add one with the “+” below the list.")
            }
        }
    }

    // MARK: - Detail

    /// Swaps the detail pane between the Terminal App settings and category cards.
    /// The category side is a `NavigationStack` so the add/edit form pushes in
    /// (with a free back button) instead of opening as a modal sheet.
    @ViewBuilder
    private var detailColumn: some View {
        switch viewModel.selection {
        case .terminalApp, .commandOutput, .currentDirectory:
            globalPane(viewModel.selection)
        case .category, .none:
            NavigationStack(path: $viewModel.formPath) {
                entryDetail
                    .navigationDestination(for: EntryFormRoute.self) { route in
                        entryForm(for: route)
                    }
            }
        }
    }

    /// Builds the add/edit form for a pushed route, resolving the edited entry
    /// from the loaded list so the form can prefill it.
    ///
    /// The ViewModel is built inside `RegisterEntryFormContainer`, which holds it
    /// in `@State`. SwiftUI re-evaluates this `navigationDestination` builder on
    /// every re-render, so calling `makeFormViewModel` directly here would mint a
    /// fresh ViewModel each time — wiping the half-entered Name and dropping Browse
    /// results. Routing through the container runs the factory exactly once per push.
    @ViewBuilder
    private func entryForm(for route: EntryFormRoute) -> some View {
        let editing: SavedEntryResponse? = {
            if case .edit(let id) = route { return viewModel.item(withID: id) }
            return nil
        }()
        let categoryID = viewModel.selectedCategoryID
        RegisterEntryFormContainer { makeFormViewModel(editing, categoryID) }
    }

}

// MARK: - Deletion-dialog bindings

private extension SettingsRootView {
    /// The settings pane for an app-global sidebar row, shared by both tabs'
    /// detail panes. Only the three global sections render; anything else is empty
    /// (the callers route category/none elsewhere).
    @ViewBuilder
    func globalPane(_ section: SettingsSection?) -> some View {
        switch section {
        case .terminalApp:
            TerminalSettingsView(viewModel: terminalViewModel)
        case .commandOutput:
            CommandOutputSettingsView(viewModel: commandOutputViewModel)
        case .currentDirectory:
            CurrentDirectorySettingsView(viewModel: currentDirectoryViewModel)
        case .category, .none:
            EmptyView()
        }
    }

    /// Bridges the optional `entryPendingDeletion` to the dialog's Bool binding.
    var entryDeletionPresented: Binding<Bool> {
        Binding(
            get: { entryPendingDeletion != nil },
            set: { if !$0 { entryPendingDeletion = nil } }
        )
    }

    /// Resolved icon URL for a File/Directory entry's chosen app, kept out of the
    /// view-builder expression so the type-checker doesn't strain on the chained row.
    func appIcon(for item: SavedEntryResponse) -> URL? {
        item.kind.appBundleIdentifier.flatMap { viewModel.appIconURL(forBundleIdentifier: $0) }
    }

    /// Entries owned by the selected category, laid out as cards.
    @ViewBuilder
    var entryDetail: some View {
        let items = viewModel.visibleItems
        if items.isEmpty {
            ContentUnavailableView(
                "No Items",
                systemImage: "tray",
                description: Text("This category has no registered items yet.")
            )
        } else {
            List {
                ForEach(items) { item in
                    EntryCard(
                        item: item,
                        appIconURL: appIcon(for: item),
                        showHistory: { historySelection = .entry(item) },
                        edit: { viewModel.beginEdit(item) },
                        requestDelete: { entryPendingDeletion = item }
                    )
                    // The row is both a drag source (payload = entry id, consumed by
                    // the sidebar for cross-category moves) and a drop target (drop an
                    // entry here to reorder it before this row). `.onMove` is NOT used:
                    // a per-row `.onDrag` hijacks the list's move gesture on macOS, so
                    // reordering must run through this drop instead.
                    .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
                    .overlay(alignment: .top) {
                        if dropTargetEntryID == item.id {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                                .padding(.horizontal, 14)
                        }
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        guard let draggedID = ids.compactMap(UUID.init(uuidString:)).first
                        else { return false }
                        Task { await viewModel.reorder(draggedID: draggedID, onto: item.id) }
                        return true
                    } isTargeted: { targeted in
                        dropTargetEntryID = targeted ? item.id : nil
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .confirmationDialog(
                "Delete Item",
                isPresented: entryDeletionPresented,
                presenting: entryPendingDeletion
            ) { item in
                Button("Delete “\(item.name)”", role: .destructive) {
                    Task { await viewModel.delete(item) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text("Deleting “\(item.name)” can’t be undone.")
            }
        }
    }

}

// MARK: - Private

/// Owns the form ViewModel in `@State` so it survives the repeated builder
/// re-evaluations SwiftUI performs on a `navigationDestination`. The factory runs
/// exactly once (at first init); SwiftUI discards any later-built instance, keeping
/// the in-progress Name/Path and Browse results intact across re-renders.
private struct RegisterEntryFormContainer: View {
    @State private var formViewModel: RegisterEntryFormViewModel

    init(make: () -> RegisterEntryFormViewModel) {
        _formViewModel = State(wrappedValue: make())
    }

    var body: some View {
        RegisterEntryForm(formViewModel: formViewModel)
    }
}

private struct HistorySelection: Identifiable {
    let entry: SavedEntryResponse?
    var id: String { entry?.id.uuidString ?? "all" }

    static let all = HistorySelection(entry: nil)
    static func entry(_ entry: SavedEntryResponse) -> HistorySelection {
        HistorySelection(entry: entry)
    }
}
