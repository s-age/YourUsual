import Foundation

/// Exposes ViewModel factories, injected with use case protocols.
@MainActor
final class PresentationContainer {
    private let registerCategory: RegisterCategoryUseCaseProtocol
    private let reorderCategories: ReorderCategoriesUseCaseProtocol
    private let deleteCategory: DeleteCategoryUseCaseProtocol
    private let editCategory: EditCategoryUseCaseProtocol
    private let registerEntry: RegisterEntryUseCaseProtocol
    private let editEntry: EditEntryUseCaseProtocol
    private let reorderEntries: ReorderEntriesUseCaseProtocol
    private let moveEntryToCategory: MoveEntryToCategoryUseCaseProtocol
    private let deleteEntry: DeleteEntryUseCaseProtocol
    private let openEntry: OpenEntryUseCaseProtocol
    private let runStreamingEntry: RunStreamingEntryUseCaseProtocol
    private let readHistory: ReadHistoryUseCaseProtocol
    private let deleteHistory: DeleteHistoryUseCaseProtocol
    private let readLaunchAtLogin: ReadLaunchAtLoginUseCaseProtocol
    private let setLaunchAtLogin: SetLaunchAtLoginUseCaseProtocol
    private let readTerminalSettings: ReadTerminalSettingsUseCaseProtocol
    private let setTerminalPreference: SetTerminalPreferenceUseCaseProtocol
    private let resolveTerminalApp: ResolveTerminalAppUseCaseProtocol
    private let resolveWorkingDirectory: ResolveWorkingDirectoryUseCaseProtocol
    private let resolveAppBundleIdentifier: ResolveAppBundleIdentifierUseCaseProtocol
    private let resolveAppIcon: ResolveAppIconUseCaseProtocol
    private let readCurrentDirectory: ReadCurrentDirectoryUseCaseProtocol
    private let setCurrentDirectory: SetCurrentDirectoryUseCaseProtocol
    private let readCommandOutputSettings: ReadCommandOutputSettingsUseCaseProtocol
    private let setCommandOutputBuffer: SetCommandOutputBufferUseCaseProtocol
    private let registerPadLayout: RegisterPadLayoutUseCaseProtocol
    private let editPadLayout: EditPadLayoutUseCaseProtocol
    private let deletePadLayout: DeletePadLayoutUseCaseProtocol
    private let reorderPadLayouts: ReorderPadLayoutsUseCaseProtocol

    /// Single shared owner of the registry read-model. Injected into the menu bar
    /// and settings ViewModels so the registry lives in one place; both observe it
    /// via `@Observable` and stay in sync without referencing each other.
    private let registry: RegistryViewModel

    /// Single shared app-icon cache, injected into both the menu bar and settings
    /// ViewModels so an icon resolved on one surface is reused by the other.
    private let appIconCache: AppIconCache

    /// One shared instance: the menu's run/output state must survive the menu
    /// window opening and closing, so it cannot be rebuilt per `body` evaluation.
    private let menuItemsViewModel: MenuItemsViewModel

    /// Shared instances for the same reason as the menu VM: each holds UI state
    /// (`SettingsViewModel.selection`/`formPath`; the settings panes' edit buffers)
    /// and is stored in its view as an injected `@Bindable` reference, so a `body`
    /// re-evaluation must not swap it for a fresh instance and drop that state.
    private let settingsViewModel: SettingsViewModel
    private let terminalSettingsViewModel: TerminalSettingsViewModel
    private let commandOutputSettingsViewModel: CommandOutputSettingsViewModel
    private let currentDirectorySettingsViewModel: CurrentDirectorySettingsViewModel

    /// Shared pad VM: it owns the selected-layout / edit-mode UI state and is the
    /// single source of truth the manager VM reloads after a mutation, so it must
    /// survive `body` re-evaluation. Built AFTER `menuItemsViewModel` — the pad
    /// delegates `.runAndStream` activation to that shared menu VM.
    private let padViewModel: PadViewModel

    init(useCases: UseCaseContainer) {
        registry = RegistryViewModel(
            readEntries: useCases.readEntries,
            readCategories: useCases.readCategories
        )
        registerCategory = useCases.registerCategory
        reorderCategories = useCases.reorderCategories
        deleteCategory = useCases.deleteCategory
        editCategory = useCases.editCategory
        registerEntry = useCases.registerEntry
        editEntry = useCases.editEntry
        reorderEntries = useCases.reorderEntries
        moveEntryToCategory = useCases.moveEntryToCategory
        deleteEntry = useCases.deleteEntry
        openEntry = useCases.openEntry
        runStreamingEntry = useCases.runStreamingEntry
        readHistory = useCases.readHistory
        deleteHistory = useCases.deleteHistory
        readLaunchAtLogin = useCases.readLaunchAtLogin
        setLaunchAtLogin = useCases.setLaunchAtLogin
        readTerminalSettings = useCases.readTerminalSettings
        setTerminalPreference = useCases.setTerminalPreference
        resolveTerminalApp = useCases.resolveTerminalApp
        resolveWorkingDirectory = useCases.resolveWorkingDirectory
        readCurrentDirectory = useCases.readCurrentDirectory
        setCurrentDirectory = useCases.setCurrentDirectory
        readCommandOutputSettings = useCases.readCommandOutputSettings
        setCommandOutputBuffer = useCases.setCommandOutputBuffer
        resolveAppBundleIdentifier = useCases.resolveAppBundleIdentifier
        resolveAppIcon = useCases.resolveAppIcon
        appIconCache = AppIconCache(resolveAppIcon: useCases.resolveAppIcon)
        registerPadLayout = useCases.registerPadLayout
        editPadLayout = useCases.editPadLayout
        deletePadLayout = useCases.deletePadLayout
        reorderPadLayouts = useCases.reorderPadLayouts

        menuItemsViewModel = MenuItemsViewModel(
            registry: registry,
            openEntry: openEntry,
            runStreamingEntry: runStreamingEntry,
            deleteHistory: deleteHistory,
            readLaunchAtLogin: readLaunchAtLogin,
            setLaunchAtLogin: setLaunchAtLogin,
            readCurrentDirectory: readCurrentDirectory,
            appIcons: appIconCache
        )
        settingsViewModel = SettingsViewModel(
            registry: registry,
            registerCategory: registerCategory,
            reorderCategories: reorderCategories,
            deleteCategory: deleteCategory,
            editCategory: editCategory,
            deleteEntry: deleteEntry,
            reorderEntries: reorderEntries,
            moveEntryToCategory: moveEntryToCategory,
            appIcons: appIconCache
        )
        terminalSettingsViewModel = TerminalSettingsViewModel(
            readSettings: readTerminalSettings,
            setPreference: setTerminalPreference,
            resolveApp: resolveTerminalApp
        )
        commandOutputSettingsViewModel = CommandOutputSettingsViewModel(
            readSettings: readCommandOutputSettings,
            setBuffer: setCommandOutputBuffer
        )
        currentDirectorySettingsViewModel = CurrentDirectorySettingsViewModel(
            readCurrentDirectory: readCurrentDirectory,
            setCurrentDirectory: setCurrentDirectory
        )
        padViewModel = PadViewModel(
            readPadLayouts: useCases.readPadLayouts,
            registerPadLayout: registerPadLayout,
            editPadLayout: editPadLayout,
            deletePadLayout: deletePadLayout,
            reorderPadLayouts: reorderPadLayouts,
            savePadCell: useCases.savePadCell,
            deletePadCell: useCases.deletePadCell,
            probeIconImage: useCases.probeIconImage,
            openEntry: openEntry,            // shared open use case
            runSlider: useCases.runSlider,
            setSliderValue: useCases.setSliderValue,
            menu: menuItemsViewModel,        // shared run path + result window
            appIcons: appIconCache,          // shared app-icon cache (menu + settings + pad)
            // Stateless across cells (state lives in its Mutex), so one shared instance
            // keyed per entry id suffices. Default 0.5s throttle interval — coarse on purpose,
            // since a slider command's cost is dominated by login-shell spawn (~250ms) or, for
            // network-backed commands (e.g. Hue over HTTP), by round-trip latency.
            sliderThrottler: SliderThrottler()
        )
    }

    func makeMenuItemsViewModel() -> MenuItemsViewModel {
        menuItemsViewModel
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        settingsViewModel
    }

    func makeTerminalSettingsViewModel() -> TerminalSettingsViewModel {
        terminalSettingsViewModel
    }

    func makeCommandOutputSettingsViewModel() -> CommandOutputSettingsViewModel {
        commandOutputSettingsViewModel
    }

    func makeCurrentDirectorySettingsViewModel() -> CurrentDirectorySettingsViewModel {
        currentDirectorySettingsViewModel
    }

    func makePadViewModel() -> PadViewModel {
        padViewModel
    }

    func makeFormViewModel(editing: SavedEntryResponse?, categoryID: UUID?) -> RegisterEntryFormViewModel {
        RegisterEntryFormViewModel(
            editing: editing,
            categoryID: categoryID,
            register: registerEntry,
            edit: editEntry,
            resolveWorkingDirectory: resolveWorkingDirectory,
            resolveAppBundleIdentifier: resolveAppBundleIdentifier,
            registry: registry
        )
    }

    func makeHistoryViewModel(entry: SavedEntryResponse?) -> RunHistoryViewModel {
        RunHistoryViewModel(
            entryID: entry?.id,
            title: entry.map { "\($0.name) History" } ?? "All History",
            readHistory: readHistory,
            deleteHistory: deleteHistory
        )
    }

    /// Triggers a reload of the shared registry — called from `Container.bootstrap()`
    /// after a one-shot migration, so the menu bar and settings (both observing the
    /// shared registry) pick up the migrated state. `PresentationContainer` is
    /// `@MainActor`, so the `Task` inherits MainActor isolation.
    ///
    /// The reload error is intentionally swallowed (`try?`): this runs at boot
    /// before any view is bound, so there is no alert channel for a thrown error
    /// to reach, and adding error plumbing for a best-effort boot refresh is not
    /// warranted. If this load fails, each list view's `.task`-driven `load()`
    /// reloads the registry on first appearance, so the migrated state is still
    /// picked up.
    func notifyRegistryChanged() {
        Task { try? await registry.load() }
    }
}
