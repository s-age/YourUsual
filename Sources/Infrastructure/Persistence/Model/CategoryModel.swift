import Foundation
import SwiftData

@Model
final class CategoryModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortIndex: Int
    // Additive column (default makes it lightweight-migratable on open, exactly like
    // `PadCellModel.customIconImageName` — see `RegistrySchema.swift`). Do NOT add a new
    // versioned schema for this; the default below IS the migration.
    var isHiddenFromMenuBar: Bool = false

    // Owning side of the category↔entry link. `.cascade` makes deleting a category
    // delete its entries in the same transaction (one `save()`), replacing the
    // former two-step UseCase cascade. `EntryModel.category` is the inverse.
    @Relationship(deleteRule: .cascade, inverse: \EntryModel.category)
    var entries: [EntryModel] = []

    init(id: UUID, name: String, sortIndex: Int, isHiddenFromMenuBar: Bool = false) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.isHiddenFromMenuBar = isHiddenFromMenuBar
    }
}
