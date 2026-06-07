import Foundation
import SwiftData

/// Common index table — shared columns used for listing, plus a discriminator and
/// a one-to-one relationship to exactly one per-type payload table. No per-type
/// columns live here, so adding a new entry type adds a table, never a nullable column.
@Model
final class EntryModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortIndex: Int
    // "browse" | "command" | "applescript". A **write-only denormalized mirror** of the
    // entry's kind, whose single source of truth is which payload relationship
    // (`browse`/`command`/`applescript`) is non-nil. Both the read path (`toDTO`) and
    // the write path (`apply`, which resolves the current kind via `Kind(payloadOf:)`)
    // derive the kind from the payload and never read this field, so it can no longer
    // diverge into a second source. Retained (still written, never read) only because
    // physically removing the
    // column needs a versioned `MigrationStage`; a future schema V2 can drop it with no
    // behavioral change.
    var entryType: String
    // Additive column (default makes it lightweight-migratable on open, exactly like
    // `PadCellModel.customIconImageName` — see `RegistrySchema.swift`). Do NOT add a new
    // versioned schema for this; the default below IS the migration.
    var isHiddenFromMenuBar: Bool = false

    // Owning category, via the inverse of `CategoryModel.entries` (cascade parent).
    // The sole source of truth for ownership (the legacy `categoryID` column it
    // replaced has been removed).
    var category: CategoryModel?

    @Relationship(deleteRule: .cascade, inverse: \BrowseEntryModel.entry)
    var browse: BrowseEntryModel?
    @Relationship(deleteRule: .cascade, inverse: \CommandEntryModel.entry)
    var command: CommandEntryModel?
    @Relationship(deleteRule: .cascade, inverse: \AppleScriptEntryModel.entry)
    var applescript: AppleScriptEntryModel?
    @Relationship(deleteRule: .cascade, inverse: \SliderEntryModel.entry)
    var slider: SliderEntryModel?

    @Relationship(deleteRule: .cascade, inverse: \CommandRunModel.entry)
    var runs: [CommandRunModel] = []

    init(id: UUID, name: String, sortIndex: Int, entryType: String, isHiddenFromMenuBar: Bool = false) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.entryType = entryType
        self.isHiddenFromMenuBar = isHiddenFromMenuBar
    }
}
