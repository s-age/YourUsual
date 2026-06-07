import Foundation

/// Root container — boots every sub-container in dependency order and exposes
/// the Presentation factories to the App scenes.
@MainActor
final class Container {
    let presentation: PresentationContainer
    /// Non-nil when the prior store was unreadable and got backed up aside; the
    /// boot layer surfaces this to the user. nil on a clean open.
    let storeRecoveryBackupURL: URL?
    /// True when an additive-evolved store was lightweight-migrated in place (no data moved);
    /// the boot layer shows a one-time "data updated" notice. False on a clean open.
    let storeWasUpgradedInPlace: Bool
    private let migrateLegacyRegistry: MigrateLegacyRegistryUseCaseProtocol
    private let ensureDefaultCategory: EnsureDefaultCategoryUseCaseProtocol
    private let normalizeTerminalPreference: NormalizeTerminalPreferenceUseCaseProtocol
    private let healRecoveredEntries: HealRecoveredEntriesUseCaseProtocol

    init() {
        let infra = InfrastructureContainer()
        let repo = RepositoryContainer(infra: infra)
        let domain = DomainContainer(repo: repo)
        let useCases = UseCaseContainer(domain: domain)
        presentation = PresentationContainer(useCases: useCases)
        storeRecoveryBackupURL = infra.storeRecoveryBackupURL
        storeWasUpgradedInPlace = infra.storeWasUpgradedInPlace
        migrateLegacyRegistry = useCases.migrateLegacyRegistry
        ensureDefaultCategory = useCases.ensureDefaultCategory
        normalizeTerminalPreference = useCases.normalizeTerminalPreference
        healRecoveredEntries = useCases.healRecoveredEntries
    }

    /// One-shot startup work (Default category seed, JSON → SwiftData import, then heal of
    /// any decode-recovery placeholders). Idempotent. The Default category is seeded first
    /// so the import can resolve entries' `category` relationship against it.
    ///
    /// Returns the notices the boot layer surfaces: a warning when a legacy registry file
    /// was present but could not be imported, and the count of entries that could not be
    /// decoded and were reset to a placeholder. Both are empty on the normal clean path.
    func bootstrap() async -> StartupNotice {
        // Canonicalize the stored terminal-preference blob once at startup so its per-read
        // recovery warning (loadPreference runs on every terminal command) fires once here
        // instead of on every run — resetting a corrupt blob or rewriting a coerced
        // launchMode. Best-effort: a failed normalize is non-fatal.
        try? normalizeTerminalPreference.execute(NormalizeTerminalPreferenceRequest())
        // Seed the Default category before the import so entries can resolve their `category`
        // relationship against it. Best-effort: a failed seed only leaves entries pointing at
        // `defaultID` with no Default row — the next launch re-seeds idempotently, so a one-off
        // failure self-heals rather than warranting a startup warning.
        try? await ensureDefaultCategory.execute(EnsureDefaultCategoryRequest())
        var migrationWarning: String?
        do {
            try await migrateLegacyRegistry.execute(MigrateLegacyRegistryRequest())
        } catch {
            migrationWarning = error.localizedDescription
        }
        // Heal after the import. A record the upgrade can no longer decode reads back as an
        // `isRecovered` placeholder; left alone it persists losslessly (the write path
        // preserves the original) but re-warns on every launch. This heal deliberately
        // converts each placeholder to its empty shape once — clearing the recovery flag,
        // which discards the undecodable original — so the warning stops. Best-effort: a
        // failed heal leaves the badge/edit-guard in place. See `HealRecoveredEntriesUseCase`.
        // Unlike `migrate` (which surfaces a warning), a heal failure is intentionally NOT
        // reported: the placeholder + its badge already tell the user, so a transient failure
        // just retries next launch rather than adding a second, redundant notice.
        let resetCount = (try? await healRecoveredEntries.execute(HealRecoveredEntriesRequest())) ?? 0
        presentation.notifyRegistryChanged()
        return StartupNotice(migrationWarning: migrationWarning, resetEntryCount: resetCount)
    }
}

/// One-shot startup notices for the boot layer to surface to the user.
struct StartupNotice {
    /// A legacy `registry.json` was present but could not be imported (read/decode
    /// failure). nil on the normal path.
    let migrationWarning: String?
    /// How many stored entries could not be decoded and were reset to an empty
    /// File/Directory placeholder. 0 on the normal path.
    let resetEntryCount: Int
}
