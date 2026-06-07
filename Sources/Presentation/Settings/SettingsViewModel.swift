import Foundation
import Observation

/// What the sidebar has selected: the global Terminal App pane, or a category.
enum SettingsSection: Hashable, Sendable {
    case terminalApp
    case commandOutput
    case currentDirectory
    case category(UUID)
}

/// One of the app-global panes pinned at the top of the Settings sidebar. Shown in
/// both the Shortcuts and Pads tabs so they stay reachable regardless of mode.
struct GlobalPane: Identifiable, Sendable {
    let section: SettingsSection
    let title: String
    let icon: String
    var id: SettingsSection { section }
}

extension SettingsSection {
    /// The app-global panes pinned at the top of the sidebar, in display order.
    /// Drives the rows in both `CategorySidebarView` and `PadsSidebarView`, so the
    /// titles/icons live in one place and can't drift between the two tabs.
    static let globalPanes: [GlobalPane] = [
        GlobalPane(section: .terminalApp, title: "Terminal App", icon: "terminal"),
        GlobalPane(section: .commandOutput, title: "Command Output", icon: "text.alignleft"),
        GlobalPane(section: .currentDirectory, title: "Current Directory", icon: "folder.badge.gearshape"),
    ]
}

/// Top-level mode toggle shown above the detail pane. `shortcuts` keeps the
/// category/entry management (plus the global Terminal/Command Output panes);
/// `pads` swaps the whole split view to launcher-pad management.
enum SettingsTab: String, Hashable, Sendable, CaseIterable {
    case shortcuts
    case pads
}

/// Detail-pane route for the add/edit form. `add` registers a new entry;
/// `edit` carries the id of the entry being modified (resolved back to a
/// `SavedEntryResponse` for prefill when the form is built).
enum EntryFormRoute: Hashable, Sendable {
    case add
    case edit(UUID)
}

@Observable
@MainActor
final class SettingsViewModel {
    /// Read-only pass-throughs to the shared registry; settings observes it via
    /// `@Observable`, so menu-bar writes propagate here without a revision counter.
    var items: [SavedEntryResponse] { registry.items }
    var categories: [CategoryResponse] { registry.categories }
    /// The sidebar selection. Drives which detail pane (and `visibleItems`) shows.
    var selection: SettingsSection?

    /// Top-level Shortcuts/Pads mode. Drives both the sidebar content and the detail.
    var tab: SettingsTab = .shortcuts

    /// The `PadLayout.id` selected in the "Pads" tab — the Settings list/editor
    /// selection only. Each launcher panel is pinned to its own `layoutID`
    /// (`PadContainerView`), so changing this selection never moves what an open
    /// panel shows.
    var selectedLayoutID: UUID?

    /// While in the Pads tab, the global pane (Terminal/Output/Directory) whose
    /// settings the detail shows instead of the pad editor — or `nil` for the
    /// editor. Lets the pinned global rows work in Pads mode without leaving it.
    var padsGlobalPane: SettingsSection?

    /// Swaps the Pads-tab detail to a global pane while staying in Pads mode, and
    /// drops the pad-list selection so re-tapping any pad returns to the editor
    /// (a fresh `selectedLayoutID` change clears `padsGlobalPane`).
    func showGlobalPaneInPads(_ pane: SettingsSection) {
        padsGlobalPane = pane
        selectedLayoutID = nil
    }

    /// Points the Settings window at the Current Directory pane (forcing the Shortcuts
    /// tab, since the global panes live there). Called when the menu bar's current-directory
    /// row opens Settings, so it lands on that pane instead of the last selection.
    func revealCurrentDirectory() {
        tab = .shortcuts
        selection = .currentDirectory
    }

    /// The selected category, when a category (not the Terminal App pane) is chosen.
    var selectedCategoryID: UUID? {
        if case .category(let id) = selection { return id }
        return nil
    }
    /// Detail-pane navigation for the add/edit form. Empty = the entry list is
    /// shown; a single route = the form is pushed onto the detail `NavigationStack`.
    /// Reset to empty when the sidebar selection changes (see `SettingsRootView`).
    var formPath: [EntryFormRoute] = []

    /// Inline "new category" editor state, shown at the bottom of the sidebar.
    var isAddingCategory = false
    var newCategoryName = ""

    /// Inline "rename category" editor state. When non-nil, that category's sidebar
    /// row swaps its label for a `TextField` seeded with `renameCategoryName`.
    var renamingCategoryID: UUID?
    var renameCategoryName = ""

    /// User-facing message for the most recent failed mutation, surfaced as an
    /// alert. Mutations set this instead of silently swallowing the error so a
    /// failed delete/move/reorder is visible rather than reverting in silence.
    var actionError: String?

    private let registry: RegistryViewModel
    private let registerCategory: RegisterCategoryUseCaseProtocol
    private let reorderCategories: ReorderCategoriesUseCaseProtocol
    private let deleteCategory: DeleteCategoryUseCaseProtocol
    private let editCategory: EditCategoryUseCaseProtocol
    private let deleteEntry: DeleteEntryUseCaseProtocol
    private let reorderEntries: ReorderEntriesUseCaseProtocol
    private let moveEntryToCategory: MoveEntryToCategoryUseCaseProtocol
    /// Shared with the menu bar so an icon resolved on either surface is reused.
    private let appIcons: AppIconCache

    /// Entries owned by the selected category. Orphan entries (category since
    /// removed) fold into the first category, mirroring the menu-bar grouping.
    var visibleItems: [SavedEntryResponse] {
        // A selection implies a category exists, so `categories.first` is the same
        // sortIndex-ordered fallback the menu-bar grouping uses (both read the shared,
        // pre-sorted registry). The orphan-fold rule itself lives in `effectiveCategoryID`.
        guard let selected = selectedCategoryID, let fallback = categories.first?.id else { return [] }
        let known = Set(categories.map(\.id))
        return items.filter { $0.effectiveCategoryID(known: known, fallback: fallback) == selected }
    }

    init(
        registry: RegistryViewModel,
        registerCategory: RegisterCategoryUseCaseProtocol,
        reorderCategories: ReorderCategoriesUseCaseProtocol,
        deleteCategory: DeleteCategoryUseCaseProtocol,
        editCategory: EditCategoryUseCaseProtocol,
        deleteEntry: DeleteEntryUseCaseProtocol,
        reorderEntries: ReorderEntriesUseCaseProtocol,
        moveEntryToCategory: MoveEntryToCategoryUseCaseProtocol,
        appIcons: AppIconCache
    ) {
        self.registry = registry
        self.registerCategory = registerCategory
        self.reorderCategories = reorderCategories
        self.deleteCategory = deleteCategory
        self.editCategory = editCategory
        self.deleteEntry = deleteEntry
        self.reorderEntries = reorderEntries
        self.moveEntryToCategory = moveEntryToCategory
        self.appIcons = appIcons
    }

    /// File URL of the cached icon for the app a browse entry opens with, if resolved;
    /// nil falls back to the SF Symbol. Forwards to the shared `AppIconCache`.
    func appIconURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        appIcons.url(forBundleIdentifier: bundleIdentifier)
    }

    func load() async {
        do {
            try await registry.load()
        } catch is CancellationError {
            // `.task`-driven: the settings window dis/appearing cancels this load.
            // Cancellation is normal control flow, not a user-facing failure — do
            // not surface it as an alert, and skip selection recovery.
            return
        } catch {
            actionError = error.localizedDescription
        }
        // Keep a valid selection: the global panes are always valid, as is a still-present
        // category. Only a now-deleted category or no selection falls back to the first
        // category. (An exhaustive switch — not a `default` — so a new section must make an
        // explicit choice here instead of being silently reset to the first category, which
        // is what dropped the current-directory pane on a cold open.)
        switch selection {
        case .terminalApp, .commandOutput, .currentDirectory:
            break
        case .category(let id) where categories.contains(where: { $0.id == id }):
            break
        case .category, .none:
            selection = categories.first.map { .category($0.id) }
        }
        await appIcons.resolve(for: items)
    }

    /// True unless the global Terminal App pane is selected — entries are added
    /// into a category, so the "+" toolbar button is disabled on that pane.
    var canAddEntry: Bool {
        if case .terminalApp = selection { return false }
        return true
    }

    /// Resolves an edit route's id back to the loaded entry for form prefill.
    func item(withID id: UUID) -> SavedEntryResponse? {
        items.first { $0.id == id }
    }

    func beginAdd() {
        formPath = [.add]
    }

    func beginEdit(_ item: SavedEntryResponse) {
        formPath = [.edit(item.id)]
    }

    /// Runs a mutating action, surfacing any failure as `actionError` rather than
    /// dropping it. Optimistic local edits are reverted by the `reloadRegistry()`
    /// the caller runs afterward, so the list stays truthful on failure.
    private func perform(_ action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Reconciles the shared registry against the store after a mutation. Both the
    /// menu bar and settings observe the shared registry, so this one reload keeps
    /// every surface in sync (replacing the old revision-counter broadcast).
    private func reloadRegistry() async {
        do { try await registry.load() } catch { actionError = error.localizedDescription }
        await appIcons.resolve(for: items)
    }

    func delete(_ item: SavedEntryResponse) async {
        await perform { try await deleteEntry.execute(DeleteEntryRequest(id: item.id)) }
        await reloadRegistry()
    }

    /// Moves an entry (dragged from the detail list) into another category.
    /// Optimistically retags it locally so it leaves the current list at once,
    /// then persists and reloads. No-op when already in the target category.
    func moveEntry(_ id: UUID, to categoryID: UUID) async {
        var updated = registry.items
        guard let index = updated.firstIndex(where: { $0.id == id }),
              updated[index].categoryID != categoryID else { return }
        updated[index] = updated[index].withCategory(categoryID)
        registry.applyOptimistic(items: updated)
        await perform {
            try await moveEntryToCategory.execute(
                MoveEntryToCategoryRequest(entryID: id, categoryID: categoryID)
            )
        }
        await reloadRegistry()
    }

    /// Drag-reorders entries within the selected category by dropping the dragged
    /// entry onto a target row: the dragged entry is re-inserted immediately before
    /// `targetID`. Driven by the row `.dropDestination` (not `.onMove`, which can't
    /// coexist with the per-row `.onDrag` used for cross-category moves on macOS).
    /// No-op when the dragged id isn't in the current category (that's a sidebar
    /// cross-category move, handled by `moveEntry`).
    func reorder(draggedID: UUID, onto targetID: UUID) async {
        guard draggedID != targetID else { return }
        var ordered = visibleItems.map(\.id)
        guard ordered.contains(draggedID), ordered.contains(targetID) else { return }
        ordered.removeAll { $0 == draggedID }
        guard let insertAt = ordered.firstIndex(of: targetID) else { return }
        ordered.insert(draggedID, at: insertAt)
        // Optimistically reorder the local cache so the row settles in place
        // immediately, before the persisted reload arrives.
        applyLocalOrder(ordered)
        await perform { try await reorderEntries.execute(ReorderEntriesRequest(orderedIDs: ordered)) }
        await reloadRegistry()
    }

    /// Mirrors `SavedEntryService.reorder` on the in-memory `items` (held in
    /// global sort order). The moved category's entries occupy a subset of array
    /// slots; this drops the new order into those same slots, leaving every
    /// other category untouched, so `visibleItems` settles immediately —
    /// before `load()` refreshes from the store.
    private func applyLocalOrder(_ orderedIDs: [UUID]) {
        let current = registry.items
        let targetIDs = Set(orderedIDs)
        let slots = current.indices.filter { targetIDs.contains(current[$0].id) }
        let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let reordered = orderedIDs.compactMap { byID[$0] }
        guard slots.count == reordered.count else { return }
        var updated = current
        for (slot, entry) in zip(slots, reordered) {
            updated[slot] = entry
        }
        registry.applyOptimistic(items: updated)
    }
}

// MARK: - Categories

extension SettingsViewModel {
    /// Whether the selected category can move up (it isn't already first).
    var canMoveSelectedCategoryUp: Bool {
        guard let index = selectedCategoryIndex else { return false }
        return index > 0
    }

    /// Whether the selected category can move down (it isn't already last).
    var canMoveSelectedCategoryDown: Bool {
        guard let index = selectedCategoryIndex else { return false }
        return index < categories.count - 1
    }

    private var selectedCategoryIndex: Int? {
        guard let id = selectedCategoryID else { return nil }
        return categories.firstIndex { $0.id == id }
    }

    /// Moves the selected category one step up (-1) or down (+1) in the sidebar.
    /// Reorders via the same use case the drag path would; optimistically applies
    /// locally so the row settles before the persisted reload.
    func moveSelectedCategory(by offset: Int) async {
        guard let index = selectedCategoryIndex else { return }
        let target = index + offset
        guard categories.indices.contains(target) else { return }
        var ordered = registry.categories
        ordered.swapAt(index, target)
        registry.applyOptimistic(categories: ordered)
        await perform {
            try await reorderCategories.execute(
                ReorderCategoriesRequest(orderedIDs: ordered.map(\.id))
            )
        }
        await reloadRegistry()
    }

    func beginAddCategory() {
        // Mutually exclusive with inline rename — drop any in-progress rename so the
        // two inline editors can't show at once.
        renamingCategoryID = nil
        renameCategoryName = ""
        newCategoryName = ""
        isAddingCategory = true
    }

    func cancelAddCategory() {
        isAddingCategory = false
        newCategoryName = ""
    }

    func commitAddCategory() async {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        isAddingCategory = false
        newCategoryName = ""
        guard !name.isEmpty else { return }
        do {
            let created = try await registerCategory.execute(RegisterCategoryRequest(name: name))
            selection = .category(created.id)
        } catch {
            actionError = error.localizedDescription
        }
        await reloadRegistry()
    }

    /// Deletes the category and every entry it contains. Selection recovers in `load()`.
    func removeCategory(_ category: CategoryResponse) async {
        await perform { try await deleteCategory.execute(DeleteCategoryRequest(id: category.id)) }
        await reloadRegistry()
    }

    /// Enters inline-rename mode for a category (the sidebar's right-click "Rename"),
    /// seeding the editor with its current name.
    func beginRenameCategory(_ category: CategoryResponse) {
        // Mutually exclusive with inline add — drop any in-progress add so the two
        // inline editors can't show at once.
        isAddingCategory = false
        newCategoryName = ""
        renameCategoryName = category.name
        renamingCategoryID = category.id
    }

    func cancelRenameCategory() {
        renamingCategoryID = nil
        renameCategoryName = ""
    }

    /// Commits an inline rename. Preserves `isHiddenFromMenuBar` (only the name
    /// changes), mirroring `toggleCategoryVisibility`'s one-field edit. An empty name
    /// is dropped silently — same as `commitAddCategory` — leaving the name unchanged.
    func commitRenameCategory() async {
        guard let id = renamingCategoryID else { return }
        let name = renameCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = categories.first { $0.id == id }
        renamingCategoryID = nil
        renameCategoryName = ""
        guard !name.isEmpty, let category, name != category.name else { return }
        await perform {
            try await editCategory.execute(
                EditCategoryRequest(
                    id: id,
                    name: name,
                    isHiddenFromMenuBar: category.isHiddenFromMenuBar
                )
            )
        }
        await reloadRegistry()
    }

    /// Flips a category's menu-bar visibility (the sidebar's right-click toggle). Keeps
    /// the current name and inverts `isHiddenFromMenuBar`, then reloads so the menu bar
    /// (which filters hidden categories) and the sidebar affordance settle.
    func toggleCategoryVisibility(_ category: CategoryResponse) async {
        await perform {
            try await editCategory.execute(
                EditCategoryRequest(
                    id: category.id,
                    name: category.name,
                    isHiddenFromMenuBar: !category.isHiddenFromMenuBar
                )
            )
        }
        await reloadRegistry()
    }
}
