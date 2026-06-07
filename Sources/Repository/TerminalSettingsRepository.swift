import Foundation

/// Bridges the global terminal-settings intent to infrastructure: persists the
/// preference via `TerminalPreferenceStore` and answers installed-app questions
/// via `InstalledAppStore`. DTO ↔ entity conversion is delegated to
/// `TerminalPreferenceMapper`; this type owns only the transport-recovery decision
/// (reset-to-default-on-decode-failure, logged) — no domain decision-making.
final class TerminalSettingsRepository: TerminalSettingsRepositoryProtocol, Sendable {
    private let preferenceStore: any TerminalPreferenceStoreProtocol
    private let installedApps: any InstalledAppStoreProtocol
    private let logger: any DiagnosticsSinkProtocol

    init(preferenceStore: any TerminalPreferenceStoreProtocol,
         installedApps: any InstalledAppStoreProtocol,
         logger: any DiagnosticsSinkProtocol) {
        self.preferenceStore = preferenceStore
        self.installedApps = installedApps
        self.logger = logger
    }

    /// Recovers a corrupt preference to `.default` **in memory only** — the corrupt blob
    /// is deliberately left in the store (we never write back on a read path; the real
    /// write-back lives in `normalizeStoredPreference()`, run once at startup). Both
    /// failure modes route here and are logged via the injected logger, so observation is
    /// single-sinked: a JSON-level corrupt blob (`store.load()` throws) and a
    /// semantically-broken one (the mapper throws) are handled identically.
    func loadPreference() -> TerminalPreference {
        do {
            guard let dto = try preferenceStore.load() else { return .default }   // absent
            let decoded = try TerminalPreferenceMapper.toEntity(dto)
            if let badMode = decoded.unparsedLaunchMode {
                // Selection is valid and kept; only the mode was unparseable. Coercing it
                // is fine, but never silently — log so the recovery stays observable.
                logger.warning(
                    "terminal launchMode '\(badMode)' unknown; defaulted to "
                    + "\(TerminalLaunchMode.default.rawValue) (selection kept)"
                )
            }
            return decoded.preference
        } catch {
            logger.warning(
                "terminal preference failed to decode (\(error.localizedDescription)); "
                + "substituted the default in memory (corrupt value left in store)"
            )
            return .default
        }
    }

    func savePreference(_ preference: TerminalPreference) throws {
        try preferenceStore.save(TerminalPreferenceMapper.toDTO(preference))
    }

    func normalizeStoredPreference() throws -> Bool {
        let dto: TerminalPreferenceDTO?
        do {
            dto = try preferenceStore.load()
        } catch {
            return try resetToDefault(reason: error.localizedDescription)   // JSON-level corrupt
        }
        guard let dto else { return false }                                 // absent: nothing to fix
        let decoded: TerminalPreferenceMapper.Decoded
        do {
            decoded = try TerminalPreferenceMapper.toEntity(dto)
        } catch {
            return try resetToDefault(reason: error.localizedDescription)   // semantically corrupt
        }
        // Decoded cleanly. A *present-but-unparseable* launchMode is not "corrupt" (the
        // selection is valid and kept), so it never reaches `resetToDefault` — but left
        // alone it would make `loadPreference()` re-warn on every terminal run. Rewrite the
        // already-coerced canonical form once here (selection preserved, mode → default) so
        // the per-read warning fires exactly once, at startup. A fully-canonical blob is
        // left untouched.
        guard let badMode = decoded.unparsedLaunchMode else { return false }
        logger.warning(
            "terminal launchMode '\(badMode)' unknown; canonicalized stored value to "
            + "\(TerminalLaunchMode.default.rawValue) (selection kept)"
        )
        try preferenceStore.save(TerminalPreferenceMapper.toDTO(decoded.preference))
        return true
    }

    /// Overwrites the stored blob with the encoded default once, logging the reason. The
    /// write side-effect is explicit here (the startup path), never hidden in a read.
    private func resetToDefault(reason: String) throws -> Bool {
        logger.warning(
            "terminal preference was corrupt at startup (\(reason)); reset the stored value to default"
        )
        try preferenceStore.save(TerminalPreferenceMapper.toDTO(.default))
        return true
    }

    func isInstalled(_ app: TerminalApp) -> Bool {
        installedApps.isInstalled(bundleIdentifier: app.bundleIdentifier)
    }

    func resolveApp(at url: URL) -> BrowsedApp? {
        guard let info = installedApps.resolveApp(at: url) else { return nil }
        // Raw identity only — classifying into known/other is the Service's domain rule.
        return BrowsedApp(bundleIdentifier: info.bundleIdentifier, name: info.name)
    }
}
