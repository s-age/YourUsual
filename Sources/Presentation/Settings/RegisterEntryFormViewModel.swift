import Foundation
import Observation

/// Parent of the add/modify form. Owns the cross-type fields (name + the Type
/// picker) and one child ViewModel per target kind. Each child holds its own
/// target + handler state, so switching the Type picker only changes which child
/// is shown — it never reaches into another type's state.
@Observable
@MainActor
final class RegisterEntryFormViewModel {
    /// Which `EntryKindPayload` the form builds — the Type picker's selection. Named
    /// for the payload it produces, distinct from the persisted `Constants.TargetKind`
    /// (the orthogonal target axis: `path`/`command`/`applescript`).
    enum EntryKind: String, CaseIterable {
        case browse
        case command
        case appleScript
        case slider
    }

    var name = ""
    var entryKind: EntryKind = .browse
    /// Whether the entry shows in the menu bar (inverse of the persisted
    /// `isHiddenFromMenuBar`). Only meaningful when editing — the register path does not
    /// carry the flag (new entries are created visible), so the View gates the toggle on
    /// `isEditing`.
    var showsInMenuBar = true

    let browseForm: BrowseEntryFormViewModel
    let commandForm: CommandEntryFormViewModel
    let applescriptForm: AppleScriptEntryFormViewModel
    let sliderForm: SliderEntryFormViewModel

    private(set) var isSaving = false
    private(set) var validationMessage: String?

    /// Snapshot of the loaded state, taken in `init`. `isDirty` compares the live
    /// fields against it to gate the Save button.
    private let originalName: String
    private let originalKind: EntryKindPayload
    private let originalShowsInMenuBar: Bool

    private let editingID: UUID?
    /// True when editing a decode-recovery placeholder: saving overwrites the original
    /// (lost) definition, so the View confirms first. False for add / normal edit.
    let isEditingRecovered: Bool
    /// Target category for a newly registered entry (nil when editing).
    private let categoryID: UUID?
    private let register: RegisterEntryUseCaseProtocol
    private let edit: EditEntryUseCaseProtocol
    private let registry: RegistryViewModel

    init(
        editing: SavedEntryResponse?,
        categoryID: UUID?,
        register: RegisterEntryUseCaseProtocol,
        edit: EditEntryUseCaseProtocol,
        resolveWorkingDirectory: ResolveWorkingDirectoryUseCaseProtocol,
        resolveAppBundleIdentifier: ResolveAppBundleIdentifierUseCaseProtocol,
        registry: RegistryViewModel
    ) {
        self.register = register
        self.edit = edit
        self.registry = registry
        self.editingID = editing?.id
        self.isEditingRecovered = editing?.isRecovered ?? false
        self.categoryID = categoryID

        browseForm = BrowseEntryFormViewModel(
            resolveWorkingDirectory: resolveWorkingDirectory,
            resolveAppBundleIdentifier: resolveAppBundleIdentifier
        )
        commandForm = CommandEntryFormViewModel(resolveWorkingDirectory: resolveWorkingDirectory)
        applescriptForm = AppleScriptEntryFormViewModel()
        sliderForm = SliderEntryFormViewModel()

        // Resolve the loaded state into locals first. `@Observable` turns `name`
        // and `entryKind` into computed accessors whose get/set call methods on
        // `self`, so they can't be touched until every stored property (including
        // `originalName`/`originalKind`) is initialized.
        var resolvedName = ""
        var resolvedEntryKind: EntryKind = .browse
        // New entries default visible; an edited entry prefills from its stored flag.
        let resolvedShowsInMenuBar = !(editing?.isHiddenFromMenuBar ?? false)

        if let editing {
            resolvedName = editing.name
            switch editing.kind {
            case .browse(let browse):
                resolvedEntryKind = .browse
                browseForm.load(browse)
            case .command(let command):
                resolvedEntryKind = .command
                commandForm.load(command)
            case .appleScript(let script):
                resolvedEntryKind = .appleScript
                applescriptForm.load(script)
            case .slider(let slider):
                resolvedEntryKind = .slider
                sliderForm.load(slider)
            }
        }

        // Snapshot for `isDirty`. The child `buildKind()` calls read the children
        // (separate, fully-initialized objects) — never `self` — so they're safe
        // before `name`/`entryKind` are assigned below.
        originalName = resolvedName
        switch resolvedEntryKind {
        case .browse:      originalKind = browseForm.buildKind()
        case .command:     originalKind = commandForm.buildKind()
        case .appleScript: originalKind = applescriptForm.buildKind()
        case .slider:      originalKind = sliderForm.buildKind()
        }
        originalShowsInMenuBar = resolvedShowsInMenuBar

        // All stored properties are now set — safe to drive the observable fields.
        name = resolvedName
        entryKind = resolvedEntryKind
        showsInMenuBar = resolvedShowsInMenuBar
    }

    /// True when modifying an existing entry (vs. registering a new one). The menu-bar
    /// visibility toggle is shown only here, since the register path does not carry it.
    var isEditing: Bool { editingID != nil }

    /// Title for the form's navigation bar.
    var title: String { editingID == nil ? "New Item" : "Edit Item" }

    /// Whether any field differs from the loaded state. Drives Save enablement
    /// so an untouched form (or a re-opened entry with no changes) can't submit.
    var isDirty: Bool {
        name != originalName
            || activeKind() != originalKind
            || showsInMenuBar != originalShowsInMenuBar
    }

    /// Returns true on success (caller dismisses). `isSaving`: false → true → false.
    func submit() async -> Bool {
        isSaving = true
        defer { isSaving = false }

        let kind = activeKind()

        do {
            if let editingID {
                _ = try await edit.execute(
                    EditEntryRequest(
                        id: editingID, name: name, kind: kind,
                        isHiddenFromMenuBar: !showsInMenuBar
                    )
                )
            } else {
                _ = try await register.execute(
                    RegisterEntryRequest(name: name, kind: kind, categoryID: categoryID)
                )
            }
            validationMessage = nil
            // Best-effort refresh of the shared registry so the lists settle now;
            // the save already succeeded, so a reload failure must not surface as a
            // "validation" error — the lists also refresh on the next `.task`.
            try? await registry.load()
            return true
        } catch let error as ValidationError {
            validationMessage = error.errorDescription
            return false
        } catch let error as OperationError {
            validationMessage = error.errorDescription
            return false
        } catch {
            validationMessage = "Unexpected error"
            return false
        }
    }

    private func activeKind() -> EntryKindPayload {
        switch entryKind {
        case .browse:      return browseForm.buildKind()
        case .command:     return commandForm.buildKind()
        case .appleScript: return applescriptForm.buildKind()
        case .slider:      return sliderForm.buildKind()
        }
    }
}
