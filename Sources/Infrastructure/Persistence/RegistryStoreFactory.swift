import Foundation
import os
import SwiftData

enum RegistryStoreFactory {
    private static let log = Logger(subsystem: "com.yourusual.app", category: "RegistryStoreFactory")

    /// Outcome of opening the store: the live container plus how it was recovered, if at all.
    /// At most one recovery signal is set — `recoveredBackupURL` (tier 3, store moved aside) and
    /// `wasUpgradedInPlace` (tier 2, lightweight-migrated in place) are mutually exclusive; both
    /// are absent/false on a clean tier-1 open. The boot layer surfaces each to the user.
    struct StoreBoot {
        let container: ModelContainer
        /// Tier 3: set to where the previous, unreadable store was backed up before recreating.
        let recoveredBackupURL: URL?
        /// Tier 2: true when an additive-evolved store was recovered in place via automatic
        /// lightweight migration (no data moved). Drives a one-time "data updated" notice.
        let wasUpgradedInPlace: Bool
    }

    /// Opens — and, when needed, migrates — the shared container for all models,
    /// in three tiers, only ever moving the user's data aside as a last resort:
    ///
    /// 1. **Staged open** via `RegistryMigrationPlan`. This applies a real
    ///    version-bumped stage (e.g. a future V2→V3) and is the normal path for a
    ///    store whose checksum already matches the current schema.
    /// 2. **Automatic-lightweight fallback** (no migration plan). The staged plan
    ///    identifies a store by its *model checksum*, not just the `"2.0.0"`
    ///    version-identifier string. Our schema evolves by folding additive,
    ///    optional columns/tables into V2 *without* bumping the identifier (see
    ///    `RegistrySchema.swift`), so every additive change gives V2 a new
    ///    checksum. A store written by an earlier build then carries a `"2.0.0"`
    ///    checksum that matches no schema the plan knows, and the staged open
    ///    fails with `NSCocoaErrorDomain 134504` ("Cannot use staged migration
    ///    with an unknown model version"). Re-opening **without** the plan lets
    ///    CoreData's automatic lightweight migration key off the per-entity
    ///    version hashes instead and apply the additive delta in place — the
    ///    store is recovered with its data intact and nothing is moved aside.
    /// 3. **Back up + recreate** only if the store is genuinely unreadable. NEVER
    ///    silently delete the user's data: move it aside to
    ///    `registry.store.corrupt-<timestamp>` and recreate an empty store,
    ///    surfacing the backup location so the caller can tell the user. If even
    ///    the backup move fails, the original error propagates — fail loud rather
    ///    than wipe.
    static func makeContainer() throws -> StoreBoot {
        let dir = try storeDirectory()
        let url = dir.appending(path: "registry.store", directoryHint: .notDirectory)
        return try makeContainer(at: url)
    }

    /// The three-tier open against an explicit store `url`. Split out from `makeContainer()`
    /// (which supplies the Application Support URL) so the tier transitions — and crucially
    /// that an *openable* store is **never** moved aside (`recoveredBackupURL == nil`) — can be
    /// exercised by integration tests against a temp store. `internal` for `@testable` reach.
    static func makeContainer(at url: URL) throws -> StoreBoot {
        let schema = Schema(versionedSchema: RegistrySchemaV2.self)
        let config = ModelConfiguration(url: url)

        // Tier 1: staged open.
        do {
            let container = try ModelContainer(for: schema,
                                               migrationPlan: RegistryMigrationPlan.self,
                                               configurations: config)
            return StoreBoot(container: container, recoveredBackupURL: nil, wasUpgradedInPlace: false)
        } catch {
            // Tier 1's ModelContainer init threw, so nothing is bound to release — the
            // partially-opened CoreData stack is torn down before the throw propagates, so the
            // SQLite lock/WAL is freed by the time tier 2 reopens the same `url` below.
            log.error("""
                Staged open of registry store failed: \(error.localizedDescription, privacy: .public). \
                Retrying with automatic lightweight migration (no plan).
                """)
        }

        // Tier 2: automatic-lightweight fallback. Recovers an additive-evolved store in place —
        // no data is moved aside on success.
        //
        // CAVEAT (fail-loud principle is weakened here): CoreData's automatic lightweight
        // migration is only safe for *additive* changes. A non-additive change to a shared
        // `@Model` (renamed/removed property) would be inferred as drop+add and **silently lose
        // that column's data while still returning success** — bypassing the tier-3 backup. The
        // only guard against that is the additive-only schema discipline documented in
        // `RegistrySchema.swift`; do not introduce a non-additive change without the per-version
        // schema + `.custom` stage there. (A genuine *type* change makes lightweight migration
        // throw, which correctly falls through to tier 3.)
        do {
            let container = try ModelContainer(for: schema, configurations: config)
            log.notice("Recovered registry store via automatic lightweight migration.")
            return StoreBoot(container: container, recoveredBackupURL: nil, wasUpgradedInPlace: true)
        } catch {
            log.error("""
                Automatic-lightweight open also failed: \(error.localizedDescription, privacy: .public). \
                Backing up the existing store and recreating.
                """)
        }

        // Tier 3: back up the unreadable store and start fresh.
        let backupURL = try backUpStore(at: url)
        let container = try ModelContainer(for: schema,
                                           migrationPlan: RegistryMigrationPlan.self,
                                           configurations: config)
        return StoreBoot(container: container, recoveredBackupURL: backupURL, wasUpgradedInPlace: false)
    }

    /// Application Support subdirectory **name** for the store. DEBUG builds (Xcode,
    /// `swift run`, `swift test`) use a separate `.dev` directory so a locally-running debug
    /// build never shares `registry.store` with the release `/Applications` app.
    ///
    /// The store path is derived from this fixed name, **not** the bundle id, so without this
    /// split every YourUsual binary — debug or release, any location — opens the *same* file.
    /// Two different-schema builds opening it concurrently corrupts it (each restamps the
    /// model checksum; the other then fails to open with `134504` and the store is moved
    /// aside). The realistic trigger is a developer running a debug build (Xcode / `swift run`)
    /// while the release `/Applications` app is also running — two processes, two schema
    /// generations, one file. Separate directories break that collision. Release keeps the
    /// canonical name, so installed users' data is unmoved.
    /// (Historical note: the old `your-usual://` URL scheme used to *auto*-launch the release
    /// app as a second process; that scheme is gone, but the debug+release concurrency case
    /// above keeps this split necessary.)
    private static var storeDirectoryName: String {
        #if DEBUG
        "com.yourusual.app.dev"
        #else
        "com.yourusual.app"
        #endif
    }

    /// Application Support subdirectory for the store, created `0o700` so only the
    /// owning user can read the registry (commands, paths) and run history.
    private static func storeDirectory() throws -> URL {
        let support = URL.applicationSupportDirectory
        let dir = support.appending(path: storeDirectoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // createDirectory only applies attributes on creation; re-assert 0o700 on a
        // pre-existing directory. Best-effort — a failure here is not fatal.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: dir.path
        )
        return dir
    }

    /// Moves the store and its WAL/SHM sidecars aside to a timestamped
    /// `.corrupt-<timestamp>` name so a fresh store can be created without losing
    /// the old data. Returns the backup URL of the main store file. Throws if a
    /// present file cannot be moved (the caller treats that as fatal — no wipe).
    private static func backUpStore(at url: URL) throws -> URL {
        let fileManager = FileManager.default
        let backupURL = URL(fileURLWithPath: url.path + ".corrupt-" + backupStamp())
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let target = URL(fileURLWithPath: backupURL.path + suffix)
            try fileManager.moveItem(at: source, to: target)
        }
        return backupURL
    }

    private static func backupStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
