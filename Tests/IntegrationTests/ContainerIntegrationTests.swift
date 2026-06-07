import Synchronization
import XCTest
@testable import YourUsual

/// Integration coverage for the DI graph (`plans/usual-core/di.md` test note).
///
/// Two complementary stacks are exercised:
///
/// 1. The real `Container()` — asserts each `PresentationContainer` factory
///    produces a usable ViewModel. These assertions read only the ViewModels'
///    deterministic initial state, so they never write to disk and never
///    pollute the user's `~/Library`.
///
/// 2. A hand-wired graph that mirrors `Container.init()` but substitutes an
///    in-memory `EntryStoreProtocol` at the infrastructure boundary. The
///    `SavedEntryRepository`, `SavedEntryService`, and every use case are the real
///    types — only the leaf store is replaced, which is the documented
///    integration pattern (mock the infrastructure data source, keep the rest
///    real). This drives a full register → load round-trip.
///
/// Limitation: `EntryStore` hardcodes its Application Support path in
/// `init()` and exposes no file-path seam, so the real `Container()`'s registry
/// cannot be pointed at a temporary file. The round-trip therefore runs through
/// the in-memory store rather than the real `EntryStore` against a temp
/// file. No on-disk registry is created, so `tearDown` has no file to remove.
@MainActor
final class ContainerIntegrationTests: XCTestCase {
    private var container: Container!

    // Hand-wired real graph backed by the in-memory store.
    private var store: InMemoryEntryStore!
    private var registerEntry: RegisterEntryUseCaseProtocol!
    private var menuItems: MenuItemsViewModel!

    override func setUp() async throws {
        try await super.setUp()

        container = Container()

        store = InMemoryEntryStore()
        let registryRepository = SavedEntryRepository(store: store, logger: MockDiagnosticsLogger())
        let categoryRepository = CategoryRepository(store: InMemoryCategoryStore())
        let categoryService = CategoryService(repository: categoryRepository)
        let browseLauncher = BrowseLauncherRepository(workspace: WorkspaceLauncher())
        let commandLauncher = CommandLauncherRepository(
            processRunner: ProcessRunner(),
            terminalLauncher: TerminalLauncher(reuseWindowStore: ReuseWindowStore())
        )
        let appleScriptLauncher = AppleScriptLauncherRepository(appleScriptRunner: AppleScriptRunner())
        let notifierRepository = NotifierRepository(notifier: NotificationDataSource())
        let registryService = SavedEntryService(repository: registryRepository)
        let browseService = BrowseLauncherService(launcher: browseLauncher)
        let appleScriptService = AppleScriptRunnerService(launcher: appleScriptLauncher)
        let terminalSettingsRepository = TerminalSettingsRepository(
            preferenceStore: TerminalPreferenceStore(),
            installedApps: InstalledAppStore(),
            logger: MockDiagnosticsLogger()
        )
        let commandService = CommandRunnerService(launcher: commandLauncher)
        let terminalSettingsService = TerminalSettingsService(repository: terminalSettingsRepository)
        let notificationService = NotificationService(notifier: notifierRepository)

        // Combined in-memory store that handles all transaction staging and routes
        // entry staging to the shared InMemoryEntryStore so the UseCase-owned
        // transaction round-trip is visible to SavedEntryRepository reads.
        let combinedStore = InMemoryCombinedStore(entryStore: store)
        let db = RegistryDatabaseGateway(runner: combinedStore)

        registerEntry = RegisterEntryUseCase(entries: registryService, db: db)
        let readEntries = ReadEntriesUseCase(entries: registryService)
        let readCategories = ReadCategoriesUseCase(categories: categoryService)
        // Real current-directory stack (file-backed store at a TEMP path so the test never
        // touches the user's real ~/Library/Application Support state + filesystem-backed resolver).
        let currentDirectoryService = CurrentDirectoryService(
            repository: CurrentDirectoryRepository(
                store: CurrentDirectoryFileStore(
                    fileURL: FileManager.default.temporaryDirectory
                        .appending(path: "yu-test-current-directory-\(UUID().uuidString)")
                )
            )
        )
        let resolver = WorkingDirectoryResolver(
            repository: FileSystemRepository(probe: DirectoryProbe())
        )
        let openEntry = OpenEntryUseCase(
            browse: browseService,
            command: commandService,
            notification: notificationService,
            terminalSettings: terminalSettingsService,
            currentDirectory: currentDirectoryService,
            resolver: resolver
        )
        let historyService = RunHistoryService(repository: MockRunHistoryRepository())
        let commandOutputSettings = CommandOutputSettingsService(
            repository: CommandOutputSettingsRepository(store: CommandOutputPreferenceStore())
        )
        let runStreamingEntry = RunStreamingEntryUseCase(
            command: commandService,
            appleScript: appleScriptService,
            notification: notificationService,
            history: historyService,
            db: db,
            diagnostics: DiagnosticsLogger(sink: OSDiagnosticsLogger(category: "IntegrationTest")),
            outputSettings: commandOutputSettings,
            currentDirectory: currentDirectoryService,
            resolver: resolver
        )
        let deleteHistory = DeleteHistoryUseCase(db: db)
        let registry = RegistryViewModel(readEntries: readEntries, readCategories: readCategories)
        menuItems = MenuItemsViewModel(
            registry: registry,
            openEntry: openEntry,
            runStreamingEntry: runStreamingEntry,
            deleteHistory: deleteHistory,
            readLaunchAtLogin: MockReadLaunchAtLoginUseCase(),
            setLaunchAtLogin: MockSetLaunchAtLoginUseCase(),
            readCurrentDirectory: ReadCurrentDirectoryUseCase(
                currentDirectory: currentDirectoryService, resolver: resolver
            ),
            appIcons: makeTestAppIconCache()
        )
    }

    override func tearDown() async throws {
        menuItems = nil
        registerEntry = nil
        store = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func registerSampleItem(name: String) async throws {
        _ = try await registerEntry.execute(
            RegisterEntryRequest(name: name, kind: .browse(BrowsePayload(path: "/tmp/example.txt", app: .default)))
        )
    }

    private func makeSampleResponse() -> SavedEntryResponse {
        SavedEntryResponse(
            id: UUID(),
            name: "Prefilled",
            kind: .browse(BrowsePayload(path: "/tmp/edit.txt", app: .default))
        )
    }

    // MARK: - makeMenuItemsViewModel

    func testMakeMenuItemsViewModel_producesViewModelWithNoItemsBeforeLoad() {
        let viewModel = container.presentation.makeMenuItemsViewModel()
        XCTAssertTrue(viewModel.items.isEmpty)
    }

    // MARK: - makeSettingsViewModel

    func testMakeSettingsViewModel_producesViewModelWithNoItemsBeforeLoad() {
        let viewModel = container.presentation.makeSettingsViewModel()
        XCTAssertTrue(viewModel.items.isEmpty)
    }

    func testMakeSettingsViewModel_producesViewModelWithEmptyFormPathInitially() {
        let viewModel = container.presentation.makeSettingsViewModel()
        XCTAssertTrue(viewModel.formPath.isEmpty)
    }

    // MARK: - makeFormViewModel

    func testMakeFormViewModel_addMode_startsWithEmptyName() {
        let viewModel = container.presentation.makeFormViewModel(editing: nil, categoryID: nil)
        XCTAssertEqual(viewModel.name, "")
    }

    func testMakeFormViewModel_editMode_prefillsName() {
        let viewModel = container.presentation.makeFormViewModel(editing: makeSampleResponse(), categoryID: nil)
        XCTAssertEqual(viewModel.name, "Prefilled")
    }

    func testMakeFormViewModel_editMode_prefillsTargetPath() {
        let viewModel = container.presentation.makeFormViewModel(editing: makeSampleResponse(), categoryID: nil)
        XCTAssertEqual(viewModel.browseForm.path, "/tmp/edit.txt")
    }

    // MARK: - Round-trip through the real registry stack (in-memory store)

    func testLoad_emptyStore_surfacesNoItems() async {
        await menuItems.load()
        XCTAssertTrue(menuItems.items.isEmpty)
    }

    func testRegisterThenLoad_surfacesOneItem() async throws {
        try await registerSampleItem(name: "Editor")
        await menuItems.load()
        XCTAssertEqual(menuItems.items.count, 1)
    }

    func testRegisterThenLoad_surfacesSavedEntryName() async throws {
        try await registerSampleItem(name: "Editor")
        await menuItems.load()
        XCTAssertEqual(menuItems.items.first?.name, "Editor")
    }
}

// MARK: - In-memory infrastructure boundary

/// In-memory `EntryStoreProtocol` standing in for `EntryStore`'s on-disk
/// JSON persistence. Lets the real repository/service/use-case graph run a
/// register → load round-trip without touching the filesystem.
private final class InMemoryEntryStore: EntryStoreProtocol, Sendable {
    private let storage = Mutex<RegistryDTO?>(nil)

    func fetchAllEntries() throws -> RegistryDTO {
        storage.withLock { $0 } ?? RegistryDTO(items: [])
    }

    /// Internal helper for `InMemoryCombinedStore.stageReplaceAllEntries`. Mirrors the
    /// real store's preserve rule: a preserved id with an existing row keeps that row
    /// (the placeholder DTO is discarded); everything else takes the incoming value.
    func store(_ dto: RegistryDTO, preservingIDs: Set<UUID>) {
        storage.withLock { current in
            let existingByID = Dictionary(
                uniqueKeysWithValues: (current?.items ?? []).map { ($0.id, $0) }
            )
            let merged = dto.items.map { item -> RegisteredItemDTO in
                if preservingIDs.contains(item.id), let kept = existingByID[item.id] { return kept }
                return item
            }
            current = RegistryDTO(items: merged)
        }
    }
}

/// In-memory `CategoryStoreProtocol` standing in for the SwiftData category
/// store. Lets the real category repository/service/use-case graph run without
/// touching the filesystem.
private final class InMemoryCategoryStore: CategoryStoreProtocol, Sendable {
    private let storage = Mutex<[CategoryDTO]>([])

    func fetchAllCategories() throws -> [CategoryDTO] {
        storage.withLock { $0 }
    }
}

/// Combined `TransactionRunnerProtocol` + `TxContextProtocol` for integration
/// tests. Runs `body` synchronously (no real DB transaction) and routes staging ops
/// to the shared in-memory stores so round-trips are visible to reads.
private final class InMemoryCombinedStore: TransactionRunnerProtocol, TxContextProtocol, Sendable {
    private let entryStore: InMemoryEntryStore
    private let historyStorage = Mutex<[RunRecordDTO]>([])

    init(entryStore: InMemoryEntryStore) {
        self.entryStore = entryStore
    }

    // MARK: - TransactionRunnerProtocol

    func transaction<T: Sendable>(
        _ body: @Sendable (any TxContextProtocol) throws -> T
    ) async throws -> T {
        try body(self)
    }

    // MARK: - TxContextProtocol (synchronous staging)

    func stageInsertRun(_ run: RunRecordDTO) throws {
        historyStorage.withLock { $0.append(run) }
    }

    func stageDeleteRun(id: UUID) throws {
        historyStorage.withLock { $0.removeAll { $0.id == id } }
    }

    func stageDeleteAllRuns(forEntry id: UUID) throws {
        historyStorage.withLock { $0.removeAll { $0.entryID == id } }
    }

    func stageDeleteAllRuns() throws {
        historyStorage.withLock { $0.removeAll() }
    }

    func stageReplaceAllEntries(_ dto: RegistryDTO, preservingIDs: Set<UUID>) throws {
        entryStore.store(dto, preservingIDs: preservingIDs)
    }

    func stageReplaceAllCategories(_ dtos: [CategoryDTO]) throws {
        // Categories not exercised in these integration tests — stub only.
    }

    // Pad tables not exercised in these integration tests — stubs only.
    func stageInsertPadLayout(_ dto: PadLayoutDTO) throws {}
    func stageUpdatePadLayout(_ dto: PadLayoutDTO) throws {}
    func stageDeletePadLayout(id: UUID) throws {}
    func stageReplacePadCells(layoutID: UUID, cells: [PadCellDTO]) throws {}
}
