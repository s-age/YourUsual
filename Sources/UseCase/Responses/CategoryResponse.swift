import Foundation

struct CategoryResponse: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let sortIndex: Int
    /// When true, this category and its entries are omitted from the menu bar listing
    /// (they remain visible in the Pad and in Settings).
    let isHiddenFromMenuBar: Bool

    /// Explicit init with a visibility default so call sites that predate the flag stay
    /// green (the synthesized memberwise init would otherwise require it everywhere).
    init(id: UUID, name: String, sortIndex: Int, isHiddenFromMenuBar: Bool = false) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.isHiddenFromMenuBar = isHiddenFromMenuBar
    }
}

// MARK: - EntryCategory → CategoryResponse

extension CategoryResponse {
    init(from category: EntryCategory) {
        self.init(
            id: category.id, name: category.name, sortIndex: category.sortIndex,
            isHiddenFromMenuBar: category.isHiddenFromMenuBar
        )
    }
}
