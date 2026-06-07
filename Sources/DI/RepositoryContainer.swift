import Foundation

/// Holds repository instances, injected with infrastructure protocols.
final class RepositoryContainer: Sendable {
    let entryRepository: any SavedEntryRepositoryProtocol
    let legacyRegistryRepository: any LegacyRegistryRepositoryProtocol
    let categoryRepository: any CategoryRepositoryProtocol
    let browseLauncher: any BrowseLauncherRepositoryProtocol
    let commandLauncher: any CommandLauncherRepositoryProtocol
    let appleScriptLauncher: any AppleScriptLauncherRepositoryProtocol
    let notifier: any NotifierRepositoryProtocol
    let historyRepository: any RunHistoryRepositoryProtocol
    let launchAtLogin: any LaunchAtLoginRepositoryProtocol
    let terminalSettings: any TerminalSettingsRepositoryProtocol
    let installedApps: any InstalledAppRepositoryProtocol
    let commandOutputSettings: any CommandOutputSettingsRepositoryProtocol
    let currentDirectory: any CurrentDirectoryRepositoryProtocol
    let fileSystemRepository: any FileSystemRepositoryProtocol
    let padLayoutRepository: any PadLayoutRepositoryProtocol
    let padCellRepository: any PadCellRepositoryProtocol
    let padIconRepository: any PadIconRepositoryProtocol
    let appIconRepository: any AppIconRepositoryProtocol
    /// UseCase-owned transaction boundary (bridges Domain `Transaction` to the
    /// Infrastructure transaction mechanism). Passed up through Domain to UseCase.
    let db: any DBProtocol
    /// Domain-facing diagnostics port (bridges to the Infrastructure `os.Logger`
    /// sink). Passed up through Domain to UseCase, like `db`.
    let diagnostics: any DiagnosticsLoggingProtocol

    init(infra: InfrastructureContainer) {
        entryRepository = SavedEntryRepository(
            store: infra.entryStore,
            logger: infra.diagnosticsLogger
        )
        legacyRegistryRepository = LegacyRegistryRepository(
            reader: infra.legacyReader,
            logger: infra.diagnosticsLogger
        )
        categoryRepository = CategoryRepository(store: infra.categoryStore)
        browseLauncher = BrowseLauncherRepository(workspace: infra.workspace)
        commandLauncher = CommandLauncherRepository(
            processRunner: infra.processRunner,
            terminalLauncher: infra.terminalLauncher
        )
        appleScriptLauncher = AppleScriptLauncherRepository(appleScriptRunner: infra.appleScriptRunner)
        notifier = NotifierRepository(notifier: infra.notifier)
        historyRepository = RunHistoryRepository(
            store: infra.historyStore,
            logger: infra.diagnosticsLogger
        )
        launchAtLogin = LaunchAtLoginRepository(store: infra.loginItem)
        terminalSettings = TerminalSettingsRepository(
            preferenceStore: infra.terminalPreference,
            installedApps: infra.installedApps,
            logger: infra.diagnosticsLogger
        )
        installedApps = InstalledAppRepository(installedApps: infra.installedApps)
        commandOutputSettings = CommandOutputSettingsRepository(store: infra.commandOutputPreference)
        currentDirectory = CurrentDirectoryRepository(store: infra.currentDirectory)
        fileSystemRepository = FileSystemRepository(probe: infra.directoryProbe)
        padLayoutRepository = PadLayoutRepository(store: infra.padStore)
        padCellRepository = PadCellRepository(store: infra.padStore)
        padIconRepository = PadIconRepository(store: infra.padIconStore)
        appIconRepository = AppIconRepository(store: infra.appIconStore)
        db = RegistryDatabaseGateway(runner: infra.transactionRunner)
        diagnostics = DiagnosticsLogger(sink: infra.diagnosticsLogger)
    }
}
