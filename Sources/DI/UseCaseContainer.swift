import Foundation

/// Holds use case instances, injected with domain service protocols.
final class UseCaseContainer: Sendable {
    let readEntries: ReadEntriesUseCaseProtocol
    let readCategories: ReadCategoriesUseCaseProtocol
    let ensureDefaultCategory: EnsureDefaultCategoryUseCaseProtocol
    let migrateLegacyRegistry: MigrateLegacyRegistryUseCaseProtocol
    let healRecoveredEntries: HealRecoveredEntriesUseCaseProtocol
    let registerCategory: RegisterCategoryUseCaseProtocol
    let reorderCategories: ReorderCategoriesUseCaseProtocol
    let deleteCategory: DeleteCategoryUseCaseProtocol
    let editCategory: EditCategoryUseCaseProtocol
    let registerEntry: RegisterEntryUseCaseProtocol
    let editEntry: EditEntryUseCaseProtocol
    let reorderEntries: ReorderEntriesUseCaseProtocol
    let moveEntryToCategory: MoveEntryToCategoryUseCaseProtocol
    let deleteEntry: DeleteEntryUseCaseProtocol
    let openEntry: OpenEntryUseCaseProtocol
    let runStreamingEntry: RunStreamingEntryUseCaseProtocol
    let readHistory: ReadHistoryUseCaseProtocol
    let deleteHistory: DeleteHistoryUseCaseProtocol
    let readLaunchAtLogin: ReadLaunchAtLoginUseCaseProtocol
    let setLaunchAtLogin: SetLaunchAtLoginUseCaseProtocol
    let readTerminalSettings: ReadTerminalSettingsUseCaseProtocol
    let normalizeTerminalPreference: NormalizeTerminalPreferenceUseCaseProtocol
    let setTerminalPreference: SetTerminalPreferenceUseCaseProtocol
    let resolveTerminalApp: ResolveTerminalAppUseCaseProtocol
    let resolveAppBundleIdentifier: ResolveAppBundleIdentifierUseCaseProtocol
    let resolveAppIcon: ResolveAppIconUseCaseProtocol
    let resolveWorkingDirectory: ResolveWorkingDirectoryUseCaseProtocol
    let readCurrentDirectory: ReadCurrentDirectoryUseCaseProtocol
    let setCurrentDirectory: SetCurrentDirectoryUseCaseProtocol
    let readCommandOutputSettings: ReadCommandOutputSettingsUseCaseProtocol
    let setCommandOutputBuffer: SetCommandOutputBufferUseCaseProtocol
    let readPadLayouts: ReadPadLayoutsUseCaseProtocol
    let registerPadLayout: RegisterPadLayoutUseCaseProtocol
    let editPadLayout: EditPadLayoutUseCaseProtocol
    let deletePadLayout: DeletePadLayoutUseCaseProtocol
    let reorderPadLayouts: ReorderPadLayoutsUseCaseProtocol
    let savePadCell: SavePadCellUseCaseProtocol
    let deletePadCell: DeletePadCellUseCaseProtocol
    let probeIconImage: ProbeIconImageUseCaseProtocol
    let runSlider: RunSliderUseCaseProtocol
    let setSliderValue: SetSliderValueUseCaseProtocol

    init(domain: DomainContainer) {
        readEntries = ReadEntriesUseCase(entries: domain.entryService)
        readCategories = ReadCategoriesUseCase(categories: domain.categoryService)
        ensureDefaultCategory = EnsureDefaultCategoryUseCase(categories: domain.categoryService, db: domain.db)
        migrateLegacyRegistry = MigrateLegacyRegistryUseCase(migration: domain.legacyMigrationService, db: domain.db)
        healRecoveredEntries = HealRecoveredEntriesUseCase(entries: domain.entryService, db: domain.db)
        registerCategory = ValidationAsyncUseCaseDecorator(
            decoratee: RegisterCategoryUseCase(categories: domain.categoryService, db: domain.db)
        )
        reorderCategories = ReorderCategoriesUseCase(categories: domain.categoryService, db: domain.db)
        deleteCategory = DeleteCategoryUseCase(categories: domain.categoryService, db: domain.db)
        editCategory = ValidationAsyncUseCaseDecorator(
            decoratee: EditCategoryUseCase(categories: domain.categoryService, db: domain.db)
        )
        // Input validation is applied as a cross-cutting decorator (not open-coded
        // in the use case): the register/edit requests that carry a name invariant
        // are wrapped here (register category is wrapped above).
        registerEntry = ValidationAsyncUseCaseDecorator(
            decoratee: RegisterEntryUseCase(entries: domain.entryService, db: domain.db)
        )
        editEntry = ValidationAsyncUseCaseDecorator(
            decoratee: EditEntryUseCase(entries: domain.entryService, db: domain.db)
        )
        reorderEntries = ReorderEntriesUseCase(entries: domain.entryService, db: domain.db)
        moveEntryToCategory = MoveEntryToCategoryUseCase(
            entries: domain.entryService, categories: domain.categoryService, db: domain.db
        )
        deleteEntry = DeleteEntryUseCase(entries: domain.entryService, db: domain.db)
        openEntry = OpenEntryUseCase(
            browse: domain.browseService,
            command: domain.commandService,
            notification: domain.notificationService,
            terminalSettings: domain.terminalSettingsService,
            currentDirectory: domain.currentDirectoryService,
            resolver: domain.workingDirectoryResolver
        )
        runStreamingEntry = RunStreamingEntryUseCase(
            command: domain.commandService,
            appleScript: domain.appleScriptService,
            notification: domain.notificationService,
            history: domain.historyService,
            db: domain.db,
            diagnostics: domain.diagnostics,
            outputSettings: domain.commandOutputSettingsService,
            currentDirectory: domain.currentDirectoryService,
            resolver: domain.workingDirectoryResolver
        )
        readHistory = ReadHistoryUseCase(history: domain.historyService)
        deleteHistory = DeleteHistoryUseCase(db: domain.db)
        readLaunchAtLogin = ReadLaunchAtLoginUseCase(launchAtLogin: domain.launchAtLoginService)
        setLaunchAtLogin = SetLaunchAtLoginUseCase(launchAtLogin: domain.launchAtLoginService)
        readTerminalSettings = ReadTerminalSettingsUseCase(settings: domain.terminalSettingsService)
        normalizeTerminalPreference =
            NormalizeTerminalPreferenceUseCase(settings: domain.terminalSettingsService)
        setTerminalPreference = SetTerminalPreferenceUseCase(settings: domain.terminalSettingsService)
        resolveTerminalApp = ResolveTerminalAppUseCase(settings: domain.terminalSettingsService)
        resolveAppBundleIdentifier =
            ResolveAppBundleIdentifierUseCase(installedApps: domain.installedAppService)
        resolveAppIcon = ResolveAppIconUseCase(appIcons: domain.appIconService)
        resolveWorkingDirectory = ResolveWorkingDirectoryUseCase(resolver: domain.workingDirectoryResolver)
        readCurrentDirectory = ReadCurrentDirectoryUseCase(
            currentDirectory: domain.currentDirectoryService,
            resolver: domain.workingDirectoryResolver
        )
        setCurrentDirectory = SetCurrentDirectoryUseCase(
            currentDirectory: domain.currentDirectoryService,
            resolver: domain.workingDirectoryResolver
        )
        readCommandOutputSettings = ReadCommandOutputSettingsUseCase(settings: domain.commandOutputSettingsService)
        setCommandOutputBuffer = SetCommandOutputBufferUseCase(settings: domain.commandOutputSettingsService)
        readPadLayouts = ReadPadLayoutsUseCase(
            padService: domain.padService,
            entryService: domain.entryService
        )
        registerPadLayout = ValidationAsyncUseCaseDecorator(
            decoratee: RegisterPadLayoutUseCase(padService: domain.padService, db: domain.db)
        )
        editPadLayout = ValidationAsyncUseCaseDecorator(
            decoratee: EditPadLayoutUseCase(padService: domain.padService, db: domain.db)
        )
        deletePadLayout = DeletePadLayoutUseCase(db: domain.db)
        reorderPadLayouts = ReorderPadLayoutsUseCase(padService: domain.padService, db: domain.db)
        savePadCell = ValidationAsyncUseCaseDecorator(
            decoratee: SavePadCellUseCase(
                padService: domain.padService,
                entries: domain.entryService,
                db: domain.db
            )
        )
        deletePadCell = DeletePadCellUseCase(padService: domain.padService, db: domain.db)
        // No validation decorator — ProbeIconImageRequest carries no invariant to validate.
        probeIconImage = ProbeIconImageUseCase(padService: domain.padService)
        // Slider run/set carry no validatable invariant, so they stay bare (no decorator).
        runSlider = RunSliderUseCase(
            command: domain.commandService,
            currentDirectory: domain.currentDirectoryService,
            resolver: domain.workingDirectoryResolver
        )
        setSliderValue = SetSliderValueUseCase(
            entries: domain.entryService, db: domain.db, diagnostics: domain.diagnostics)
    }
}
