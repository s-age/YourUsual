import Foundation

/// Owns the data source / store instances — the lowest layer of the graph.
final class InfrastructureContainer {
    let entryStore: any EntryStoreProtocol
    let historyStore: any RunHistoryStoreProtocol
    let categoryStore: any CategoryStoreProtocol
    let padStore: any PadStoreProtocol
    let padIconStore: any PadIconStoreProtocol
    let appIconStore: any AppIconStoreProtocol
    /// The transaction *mechanism* (one `RegistryDatabase` actor, shared with the
    /// stores). The Repository `RegistryDatabaseGateway` drives it; UseCase owns the boundary.
    let transactionRunner: any TransactionRunnerProtocol
    /// Pure transport read of the legacy `registry.json`. The import *decision* and
    /// transaction boundary live above (Domain service + `MigrateLegacyRegistryUseCase`).
    let legacyReader: any LegacyRegistryReaderProtocol
    let workspace: any WorkspaceLauncherProtocol
    let processRunner: any ProcessRunnerProtocol
    let terminalLauncher: any TerminalLauncherProtocol
    let appleScriptRunner: any AppleScriptRunnerProtocol
    let notifier: any NotifierProtocol
    let loginItem: any LoginItemStoreProtocol
    let terminalPreference: any TerminalPreferenceStoreProtocol
    let commandOutputPreference: any CommandOutputPreferenceStoreProtocol
    /// File-backed store for the global current directory (persisted; shared with the CLI).
    let currentDirectory: any CurrentDirectoryStoreProtocol
    let installedApps: any InstalledAppStoreProtocol
    let directoryProbe: any DirectoryProbeProtocol
    /// Records non-fatal data-recovery diagnostics from the Repository layer.
    let diagnosticsLogger: any DiagnosticsSinkProtocol

    /// Non-nil when the prior store could not be opened and was backed up aside
    /// (rather than wiped). Surfaced up to the boot layer to inform the user.
    let storeRecoveryBackupURL: URL?

    /// True when an additive-evolved store was lightweight-migrated in place (no data moved).
    /// Surfaced to the boot layer for a one-time "data updated" notice.
    let storeWasUpgradedInPlace: Bool

    init() {
        let db: RegistryDatabase
        let recoveredBackupURL: URL?
        let wasUpgradedInPlace: Bool
        do {
            (db, recoveredBackupURL, wasUpgradedInPlace) = try RegistryDatabase.makeDefault()
        } catch {
            fatalError("Failed to initialize RegistryDatabase: \(error)")
        }
        storeRecoveryBackupURL = recoveredBackupURL
        storeWasUpgradedInPlace = wasUpgradedInPlace
        entryStore = db
        historyStore = db
        categoryStore = db
        padStore = db   // RegistryDatabase conforms to PadStoreProtocol
        padIconStore = PadIconStore()   // filesystem + image processing; not SwiftData
        appIconStore = AppIconStore()   // NSWorkspace icon → cached PNG; not SwiftData
        transactionRunner = db
        legacyReader = LegacyRegistryReader()
        workspace = WorkspaceLauncher()
        processRunner = ProcessRunner()
        terminalLauncher = TerminalLauncher(reuseWindowStore: ReuseWindowStore())
        appleScriptRunner = AppleScriptRunner()
        notifier = NotificationDataSource()
        loginItem = LoginItemStore()
        terminalPreference = TerminalPreferenceStore()
        commandOutputPreference = CommandOutputPreferenceStore()
        currentDirectory = CurrentDirectoryFileStore()
        installedApps = InstalledAppStore()
        directoryProbe = DirectoryProbe()
        diagnosticsLogger = OSDiagnosticsLogger(category: "DataRecovery")
    }
}
