import Foundation

struct SavedEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var kind: EntryKind
    var sortIndex: Int            // menu ordering
    var categoryID: UUID          // owning category — Default when unspecified
    /// True when this entry is a transport-recovery placeholder for a record that
    /// could not be decoded — its original kind/definition was lost. Presentation
    /// surfaces a warning; saving an edit overwrites the original blob permanently.
    /// A read-only recovery marker derived on load, never persisted (the DTO has no
    /// such field), so it is always `false` for an entry the user actually created.
    var isRecovered: Bool
    /// When true, the entry is omitted from the menu bar listing (it remains
    /// visible in the Pad and in Settings). Defaults to visible so every existing
    /// construction site is unaffected.
    var isHiddenFromMenuBar: Bool

    init(
        id: UUID = UUID(),
        name: String,
        kind: EntryKind,
        sortIndex: Int,
        categoryID: UUID = EntryCategory.defaultID,
        isRecovered: Bool = false,
        isHiddenFromMenuBar: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sortIndex = sortIndex
        self.categoryID = categoryID
        self.isRecovered = isRecovered
        self.isHiddenFromMenuBar = isHiddenFromMenuBar
    }
}
