import Foundation

/// A grouping for `SavedEntry` items. A built-in "Default" category is seeded at
/// launch as the empty-state fallback — only when no categories exist at all
/// (see `CategoryService.ensuringDefault`). It is otherwise an ordinary category:
/// once others exist it can be deleted and is not resurrected. Entries whose
/// category is unknown fall back to the first category in the menu/settings group.
///
/// Named `EntryCategory` rather than `Category` to avoid colliding with
/// `FoundationModels.Category`, which is in scope for the test target.
struct EntryCategory: Identifiable, Equatable, Sendable {
    /// Stable identity of the built-in Default category. New entries with no
    /// explicit category default to this id, so it must never change.
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let defaultName = "Default"

    let id: UUID
    var name: String
    var sortIndex: Int            // menu ordering
    /// When true, the category and its entries are omitted from the menu bar
    /// listing (they remain visible in the Pad and in Settings). Defaults to
    /// visible so every existing construction site is unaffected.
    var isHiddenFromMenuBar: Bool

    init(id: UUID = UUID(), name: String, sortIndex: Int, isHiddenFromMenuBar: Bool = false) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.isHiddenFromMenuBar = isHiddenFromMenuBar
    }

    /// The built-in Default category, ordered first.
    static func makeDefault() -> EntryCategory {
        EntryCategory(id: defaultID, name: defaultName, sortIndex: 0)
    }
}
