import Foundation

/// The editable content of an existing `SavedEntry`, bundled into one value so
/// `SavedEntryService.editing` stays within the 4-parameter limit (a protocol
/// requirement cannot declare default values, so each editable field would
/// otherwise count against `function_parameter_count`). It also gives entry edits
/// a single extension point for new editable fields. Mirrors the `PadCellDraft`
/// bundling precedent. The entry's identity (`id`), ordering (`sortIndex`), and
/// owning `categoryID` are preserved by `editing` and are not part of the content.
struct SavedEntryEdit: Equatable, Sendable {
    var name: String
    var kind: EntryKind
    /// When true, the edited entry is hidden from the menu bar listing. **No default** —
    /// every caller must state it, so applying an edit can never silently un-hide an
    /// entry by omitting this field. Tests pass it explicitly.
    var isHiddenFromMenuBar: Bool

    init(name: String, kind: EntryKind, isHiddenFromMenuBar: Bool) {
        self.name = name
        self.kind = kind
        self.isHiddenFromMenuBar = isHiddenFromMenuBar
    }
}
