import Foundation

/// Holds domain service instances, injected with repository protocols.
final class DomainContainer: Sendable {
    let entryService: any SavedEntryServiceProtocol
    let legacyMigrationService: any LegacyMigrationServiceProtocol
    let categoryService: any CategoryServiceProtocol
    let browseService: any BrowseLauncherServiceProtocol
    let commandService: any CommandRunnerServiceProtocol
    let appleScriptService: any AppleScriptRunnerServiceProtocol
    let notificationService: any NotificationServiceProtocol
    let historyService: any RunHistoryServiceProtocol
    let launchAtLoginService: any LaunchAtLoginServiceProtocol
    let terminalSettingsService: any TerminalSettingsServiceProtocol
    let installedAppService: any InstalledAppServiceProtocol
    let appIconService: any AppIconServiceProtocol
    let commandOutputSettingsService: any CommandOutputSettingsServiceProtocol
    let currentDirectoryService: any CurrentDirectoryServiceProtocol
    let workingDirectoryResolver: any WorkingDirectoryResolverProtocol
    let padService: any PadServiceProtocol
    /// UseCase-owned transaction boundary, surfaced to the UseCase layer. The
    /// protocol lives in `Domain/Services/Protocols`, so UseCase may import it
    /// without reaching into Repository. (Passed through; not a Domain Service.)
    let db: any DBProtocol
    /// Diagnostics port surfaced to the UseCase layer. (Passed through; not a
    /// Domain Service.)
    let diagnostics: any DiagnosticsLoggingProtocol

    init(repo: RepositoryContainer) {
        entryService = SavedEntryService(repository: repo.entryRepository)
        legacyMigrationService = LegacyMigrationService(
            repository: repo.entryRepository,
            legacyRepository: repo.legacyRegistryRepository
        )
        categoryService = CategoryService(repository: repo.categoryRepository)
        browseService = BrowseLauncherService(launcher: repo.browseLauncher)
        appleScriptService = AppleScriptRunnerService(launcher: repo.appleScriptLauncher)
        commandService = CommandRunnerService(launcher: repo.commandLauncher)
        notificationService = NotificationService(notifier: repo.notifier)
        historyService = RunHistoryService(repository: repo.historyRepository)
        launchAtLoginService = LaunchAtLoginService(repository: repo.launchAtLogin)
        terminalSettingsService = TerminalSettingsService(repository: repo.terminalSettings)
        installedAppService = InstalledAppService(repository: repo.installedApps)
        appIconService = AppIconService(repository: repo.appIconRepository)
        commandOutputSettingsService = CommandOutputSettingsService(repository: repo.commandOutputSettings)
        currentDirectoryService = CurrentDirectoryService(repository: repo.currentDirectory)
        workingDirectoryResolver = WorkingDirectoryResolver(repository: repo.fileSystemRepository)
        padService = PadService(
            layoutRepository: repo.padLayoutRepository,
            cellRepository: repo.padCellRepository,
            iconRepository: repo.padIconRepository
        )
        db = repo.db
        diagnostics = repo.diagnostics
    }
}
