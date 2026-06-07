import Foundation
import SwiftData

@ModelActor
actor RegistryDatabase {

    // MARK: - Factory

    /// Returns the live database plus how the store was recovered, if at all — surfaced so the
    /// boot layer can tell the user. `recoveredBackupURL` is non-nil when an unreadable prior
    /// store was moved aside (tier 3); `wasUpgradedInPlace` is true when an additive-evolved
    /// store was lightweight-migrated in place (tier 2). Both absent on a clean open.
    static func makeDefault() throws
        -> (database: RegistryDatabase, recoveredBackupURL: URL?, wasUpgradedInPlace: Bool) {
        let boot = try RegistryStoreFactory.makeContainer()
        return (RegistryDatabase(modelContainer: boot.container),
                boot.recoveredBackupURL,
                boot.wasUpgradedInPlace)
    }

    // MARK: - RunHistoryStoreProtocol — reads only

    /// History reads are intentionally **capped to the most recent runs** rather than
    /// returning the whole table: the history UI only shows recent activity, and an
    /// unbounded fetch would grow with the store. Sorted newest-first, so this keeps
    /// the latest `historyFetchLimit` and drops older rows from the *result* (the rows
    /// stay on disk; this is a read cap, not a delete). Bump the constant if the UI
    /// ever needs a deeper window.
    private static let historyFetchLimit = 200

    func fetch(forEntry id: UUID) throws -> [RunRecordDTO] {
        let entryID = id
        var descriptor = FetchDescriptor<CommandRunModel>(
            predicate: #Predicate { $0.entryID == entryID },
            sortBy: [SortDescriptor(\.executedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.historyFetchLimit
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor).map(Self.toDTO)
    }

    func fetchAllRuns() throws -> [RunRecordDTO] {
        var descriptor = FetchDescriptor<CommandRunModel>(
            sortBy: [SortDescriptor(\.executedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.historyFetchLimit
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor).map(Self.toDTO)
    }

    // MARK: - @Model ↔ DTO (private — @Model must never escape the actor)

    private static func toDTO(_ m: CommandRunModel) -> RunRecordDTO {
        RunRecordDTO(
            id: m.id,
            entryID: m.entryID,
            entryName: m.entryName,
            executedAt: m.executedAt,
            outcomeKind: m.outcomeKind,
            commandLine: m.commandLine,
            exitCode: m.exitCode.map(Int32.init),
            stdout: m.stdout,
            stderr: m.stderr
        )
    }

}

// MARK: - Protocol conformances

extension RegistryDatabase: RunHistoryStoreProtocol {}
