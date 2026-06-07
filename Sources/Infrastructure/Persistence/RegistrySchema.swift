import Foundation
import SwiftData

/// Versioned snapshot of the registry's SwiftData schema.
///
/// This is the first *versioned* schema for the store. Existing on-disk stores
/// were created from these same model definitions without a version identifier;
/// SwiftData matches a store to a schema by the model structure (not the version
/// string), so those stores are recognized as already at V1 and open with no
/// migration. Future schema changes add `RegistrySchemaV2`, … plus a matching
/// `MigrationStage`, so stores migrate **in place** instead of being discarded.
enum RegistrySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [EntryModel.self, CommandRunModel.self, CategoryModel.self,
         BrowseEntryModel.self, CommandEntryModel.self, AppleScriptEntryModel.self]
    }
}

/// Second (current) versioned schema — adds the Launcher Pad tables (`PadLayoutModel`,
/// `PadCellModel`) on top of V1. No existing column is renamed or retyped, so the
/// V1→V2 migration is `.lightweight` (only new tables are introduced).
///
/// Subsequent additive changes are **folded into this same V2 schema**, never a new
/// versioned schema. This codebase shares one top-level set of `@Model` classes across all
/// schema versions (rather than Apple's per-version nested copies), and SwiftData snapshots a
/// `VersionedSchema`'s checksum from the *current* model definitions. So any model property
/// added to a shared class is visible to *every* `VersionedSchema` that lists it: a
/// `RegistrySchemaV3` reusing those same classes is byte-identical to V2 and crashes at boot
/// with `Duplicate version checksums detected`.
///
/// **Gotcha — folding additive changes into V2 changes V2's checksum.** SwiftData's *staged*
/// `migrationPlan` identifies a store by its model checksum, not by the `"2.0.0"` version
/// string. Each additive column/table here gives V2 a new checksum, so a store written by an
/// earlier build carries a `"2.0.0"`-stamped checksum that matches no schema the plan knows,
/// and a staged open fails with `NSCocoaErrorDomain 134504` ("Cannot use staged migration with
/// an unknown model version"). The recovery is to open **without** the plan: CoreData's
/// automatic lightweight migration keys off the per-entity version hashes and applies the
/// additive delta in place. `RegistryStoreFactory.makeContainer` does exactly that as its
/// second tier, so these folded-in changes migrate on open without moving data aside.
/// Four have landed this way:
///   - `PadCellModel.customIconImageName` — additive optional column (nil default).
///   - `EntryModel.isHiddenFromMenuBar` — additive column with a default.
///   - `SliderEntryModel` + its inverse `EntryModel.slider` — an additive optional *table* +
///     relationship; SwiftData creates the empty table and defaults the relationship to nil
///     on open. Listed in `models` below to make the registration explicit.
///   - `PadCellModel.orientation` — additive column with a literal "horizontal" default; only
///     slider cells consult it (button cells ignore it). Lightweight-migrates on open.
///
/// A *non-additive* change later (renaming/retyping/removing an existing column) cannot be
/// folded in: it will require switching the shared models to per-version nested copies
/// (Apple's pattern) and a real `RegistrySchemaV3` + `.custom` stage.
enum RegistrySchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [EntryModel.self, CommandRunModel.self, CategoryModel.self,
         BrowseEntryModel.self, CommandEntryModel.self, AppleScriptEntryModel.self,
         SliderEntryModel.self,
         PadLayoutModel.self, PadCellModel.self]
    }
}

/// Ordered migration plan for the registry store.
///
/// New schema versions append their `VersionedSchema` to `schemas` and add a
/// `MigrationStage` (`.lightweight` for SwiftData-inferrable changes, `.custom`
/// otherwise) to `stages`. SwiftData records the store's current version and
/// applies only the outstanding stages at `ModelContainer` init — i.e. at app
/// launch, never at build time and never via an external script.
///
/// Note: additive optional columns/tables on the shared models (e.g. `isHiddenFromMenuBar`,
/// `customIconImageName`, the slider table) are folded into the current `RegistrySchemaV2`
/// and lightweight-migrate on open — they do **not** get a new version here (a new version
/// reusing the shared classes would duplicate V2's checksum). See `RegistrySchemaV2`.
enum RegistryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RegistrySchemaV1.self, RegistrySchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: RegistrySchemaV1.self, toVersion: RegistrySchemaV2.self)]
    }
}
