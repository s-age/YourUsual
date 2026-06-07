import Foundation
import SwiftData

/// Invariant — `entryID` and `entry` encode the same parent link two ways and must
/// never diverge:
///   * `entryID` (denormalized) is the **source of truth for queries/deletes** —
///     fetch/delete-by-entry use it directly, avoiding a relationship join that
///     `#Predicate` traverses unreliably.
///   * `entry` (the relationship) exists **only** to carry the cascade-delete edge
///     (`EntryModel.runs`, cascade parent), so removing an entry tears down its runs.
/// Both are set together in `RegistryDatabase.stageInsertRun`; nothing else should
/// write either field. (Dropping `entryID` outright would need a versioned
/// `MigrationStage` — without one, the column removal fails to open the existing
/// store and trips the corrupt-store backup path, so it stays for now.)
@Model
final class CommandRunModel {
    @Attribute(.unique) var id: UUID
    var entryID: UUID               // denormalized parent link — see type doc (source of truth)
    var entryName: String
    var executedAt: Date

    // Persisted discriminator for the domain `RunOutcome` enum — i.e. *which kind of
    // outcome* this record is (hence "outcomeKind", not the success/failure result,
    // which lives in `exitCode`). `RunRecordMapper` maps it to `RunOutcome` and throws
    // on an unknown value. Currently the only value is "command"; kept as a string
    // discriminator so adding a future `RunOutcome` case needs no schema migration.
    // NOTE: this is a SwiftData column — renaming it is a schema change (would need an
    // `@Attribute(originalName:)` or a `MigrationStage`), so the on-disk name stays.
    var outcomeKind: String
    var commandLine: String?
    var exitCode: Int?              // SwiftData stores Int; map ↔ Int32 at the actor boundary
    var stdout: String?
    var stderr: String?

    var entry: EntryModel?          // inverse of EntryModel.runs (cascade parent)

    init(id: UUID, entryID: UUID, entryName: String, executedAt: Date,
         outcomeKind: String, commandLine: String?, exitCode: Int?,
         stdout: String?, stderr: String?) {
        self.id = id
        self.entryID = entryID
        self.entryName = entryName
        self.executedAt = executedAt
        self.outcomeKind = outcomeKind
        self.commandLine = commandLine
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}
