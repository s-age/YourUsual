import XCTest
@testable import YourUsual

@MainActor
final class MenuItemsViewModelTests: XCTestCase {
    private var mockFetch: MockReadEntriesUseCase!
    private var mockReadCategories: MockReadCategoriesUseCase!
    private var mockOpenEntry: MockOpenEntryUseCase!
    private var mockRunStreamingEntry: MockRunStreamingEntryUseCase!
    private var mockDeleteHistory: MockDeleteHistoryUseCase!
    private var mockReadLaunchAtLogin: MockReadLaunchAtLoginUseCase!
    private var mockSetLaunchAtLogin: MockSetLaunchAtLoginUseCase!
    private var mockReadCurrentDirectory: MockReadCurrentDirectoryUseCase!
    private var registry: RegistryViewModel!
    private var sut: MenuItemsViewModel!

    override func setUp() {
        super.setUp()
        mockFetch = MockReadEntriesUseCase()
        mockReadCategories = MockReadCategoriesUseCase()
        mockOpenEntry = MockOpenEntryUseCase()
        mockRunStreamingEntry = MockRunStreamingEntryUseCase()
        mockDeleteHistory = MockDeleteHistoryUseCase()
        mockReadLaunchAtLogin = MockReadLaunchAtLoginUseCase()
        mockSetLaunchAtLogin = MockSetLaunchAtLoginUseCase()
        mockReadCurrentDirectory = MockReadCurrentDirectoryUseCase()
        registry = RegistryViewModel(readEntries: mockFetch, readCategories: mockReadCategories)
        sut = MenuItemsViewModel(
            registry: registry,
            openEntry: mockOpenEntry,
            runStreamingEntry: mockRunStreamingEntry,
            deleteHistory: mockDeleteHistory,
            readLaunchAtLogin: mockReadLaunchAtLogin,
            setLaunchAtLogin: mockSetLaunchAtLogin,
            readCurrentDirectory: mockReadCurrentDirectory,
            appIcons: makeTestAppIconCache()
        )
    }

    override func tearDown() {
        sut = nil
        registry = nil
        mockFetch = nil
        mockReadCategories = nil
        mockOpenEntry = nil
        mockRunStreamingEntry = nil
        mockDeleteHistory = nil
        mockReadLaunchAtLogin = nil
        mockSetLaunchAtLogin = nil
        mockReadCurrentDirectory = nil
        super.tearDown()
    }

    // MARK: - run refreshes the current directory

    func testRun_afterCompletion_refreshesCurrentDirectoryFromStore() async {
        // A menu-registered `your-usual cd <path>` background command changes the persisted dir;
        // on the run's `.exit` (child finished writing the state file) the menu row must reflect
        // it without a reopen.
        mockRunStreamingEntry.events = [.exit(code: 0, succeeded: true)]
        mockReadCurrentDirectory.result = CurrentDirectoryResponse(path: "/changed/by/cd")
        let item = commandItem()
        sut.run(item)
        for _ in 0..<1000 where sut.isRunning(item.id) { await Task.yield() }   // let the run settle
        XCTAssertEqual(sut.currentDirectory?.path, "/changed/by/cd")
    }

    private func browseItem() -> SavedEntryResponse {
        ItemFixtures.make(kind: .browse(BrowsePayload(path: "/tmp/file.txt", app: .default)))
    }

    private func commandItem() -> SavedEntryResponse {
        ItemFixtures.make(
            name: "List",
            kind: .command(CommandPayload(commandLine: "/bin/ls", workingDirectory: nil, sink: .background))
        )
    }

    // MARK: - load()

    func testLoad_setsItemsFromFetchUseCase() async {
        let items = [ItemFixtures.make(name: "A"), ItemFixtures.make(name: "B")]
        mockFetch.result = items

        await sut.load()

        XCTAssertEqual(sut.items, items)
    }

    func testLoad_callsFetchUseCaseOnce() async {
        await sut.load()

        XCTAssertEqual(mockFetch.callCount, 1)
    }

    func testLoad_fetchFailure_leavesItemsEmpty() async {
        mockFetch.error = OperationError.persistenceFailed(reason: "boom")

        await sut.load()

        XCTAssertEqual(sut.items, [])
    }

    func testLoad_setsLaunchAtLoginFromUseCase() async {
        mockReadLaunchAtLogin.result = true

        await sut.load()

        XCTAssertTrue(sut.launchAtLogin)
    }

    /// When the registry load fails, that (menu-content) error must win — a secondary
    /// launch-read failure must not overwrite it with its own message.
    func testLoad_registryFailure_keepsRegistryErrorOverLaunchReadFailure() async {
        mockFetch.error = OperationError.persistenceFailed(reason: "registry boom")
        mockReadLaunchAtLogin.error = OperationError.persistenceFailed(reason: "launch boom")

        await sut.load()

        XCTAssertEqual(
            sut.actionError,
            OperationError.persistenceFailed(reason: "registry boom").localizedDescription
        )
    }

    /// A failed registry load short-circuits before the launch-at-login read.
    func testLoad_registryFailure_skipsLaunchAtLoginRead() async {
        mockFetch.error = OperationError.persistenceFailed(reason: "registry boom")

        await sut.load()

        XCTAssertEqual(mockReadLaunchAtLogin.callCount, 0)
    }

    // MARK: - sections (grouping by category)

    private func categoryResponse(
        _ id: UUID, _ name: String, _ sortIndex: Int, isHiddenFromMenuBar: Bool = false
    ) -> CategoryResponse {
        CategoryResponse(id: id, name: name, sortIndex: sortIndex, isHiddenFromMenuBar: isHiddenFromMenuBar)
    }

    func testSections_groupsEntriesUnderTheirCategory() async {
        let work = UUID()
        mockReadCategories.result = [
            categoryResponse(EntryCategory.defaultID, "Default", 0),
            categoryResponse(work, "Work", 1),
        ]
        mockFetch.result = [
            ItemFixtures.make(name: "A", categoryID: EntryCategory.defaultID),
            ItemFixtures.make(name: "B", categoryID: work),
        ]

        await sut.load()

        XCTAssertEqual(sut.sections.map(\.name), ["Default", "Work"])
    }

    func testSections_ordersByCategorySortIndex() async {
        let work = UUID()
        mockReadCategories.result = [
            categoryResponse(work, "Work", 5),
            categoryResponse(EntryCategory.defaultID, "Default", 0),
        ]
        mockFetch.result = [
            ItemFixtures.make(name: "A", categoryID: EntryCategory.defaultID),
            ItemFixtures.make(name: "B", categoryID: work),
        ]

        await sut.load()

        XCTAssertEqual(sut.sections.map(\.name), ["Default", "Work"])
    }

    func testSections_placesEntryInMatchingCategory() async {
        let work = UUID()
        mockReadCategories.result = [
            categoryResponse(EntryCategory.defaultID, "Default", 0),
            categoryResponse(work, "Work", 1),
        ]
        mockFetch.result = [ItemFixtures.make(name: "B", categoryID: work)]

        await sut.load()

        XCTAssertEqual(sut.sections.first { $0.name == "Work" }?.items.map(\.name), ["B"])
    }

    func testSections_orphanEntry_foldsIntoFirstCategory() async {
        mockReadCategories.result = [categoryResponse(EntryCategory.defaultID, "Default", 0)]
        mockFetch.result = [ItemFixtures.make(name: "Orphan", categoryID: UUID())]

        await sut.load()

        XCTAssertEqual(sut.sections.first?.items.map(\.name), ["Orphan"])
    }

    func testSections_categoriesNotLoaded_keepsEntriesUnderDefault() async {
        mockReadCategories.result = []
        mockFetch.result = [ItemFixtures.make(name: "A")]

        await sut.load()

        XCTAssertEqual(sut.sections.first?.items.map(\.name), ["A"])
    }

    func testSections_noEntries_returnsCategoriesWithEmptyItems() async {
        mockReadCategories.result = [categoryResponse(EntryCategory.defaultID, "Default", 0)]
        mockFetch.result = []

        await sut.load()

        XCTAssertEqual(sut.sections.first?.items.isEmpty, true)
    }

    // MARK: - sections (menu-bar visibility filtering)

    func testSections_hiddenCategory_isExcluded() async {
        let hidden = UUID()
        mockReadCategories.result = [
            categoryResponse(EntryCategory.defaultID, "Default", 0),
            categoryResponse(hidden, "Secret", 1, isHiddenFromMenuBar: true),
        ]
        mockFetch.result = [ItemFixtures.make(name: "A", categoryID: EntryCategory.defaultID)]

        await sut.load()

        XCTAssertEqual(sut.sections.map(\.name), ["Default"])
    }

    func testSections_hiddenEntry_isExcluded() async {
        mockReadCategories.result = [categoryResponse(EntryCategory.defaultID, "Default", 0)]
        mockFetch.result = [
            ItemFixtures.make(name: "Visible", categoryID: EntryCategory.defaultID),
            ItemFixtures.make(name: "Hidden", categoryID: EntryCategory.defaultID, isHiddenFromMenuBar: true),
        ]

        await sut.load()

        XCTAssertEqual(sut.sections.first?.items.map(\.name), ["Visible"])
    }

    // An entry owned by a hidden category must not re-surface in the fallback section.
    func testSections_entryOfHiddenCategory_doesNotFoldIntoFallback() async {
        let hidden = UUID()
        mockReadCategories.result = [
            categoryResponse(EntryCategory.defaultID, "Default", 0),
            categoryResponse(hidden, "Secret", 1, isHiddenFromMenuBar: true),
        ]
        mockFetch.result = [ItemFixtures.make(name: "InSecret", categoryID: hidden)]

        await sut.load()

        let allItems = sut.sections.flatMap(\.items).map(\.name)
        XCTAssertFalse(allItems.contains("InSecret"))
    }

    // MARK: - setLaunchAtLogin(_:)

    func testSetLaunchAtLogin_passesEnabledToUseCase() {
        sut.setLaunchAtLogin(true)

        XCTAssertEqual(mockSetLaunchAtLogin.receivedEnabled, true)
    }

    func testSetLaunchAtLogin_reflectsAppliedSystemState() {
        // Requested true, but the system reports it did not take effect.
        mockSetLaunchAtLogin.result = false

        sut.setLaunchAtLogin(true)

        XCTAssertFalse(sut.launchAtLogin)
    }

    func testSetLaunchAtLogin_onFailure_fallsBackToFreshRead() {
        mockSetLaunchAtLogin.error = OperationError.persistenceFailed(reason: "boom")
        mockReadLaunchAtLogin.result = true

        sut.setLaunchAtLogin(true)

        XCTAssertTrue(sut.launchAtLogin)
    }

    // MARK: - open(_:)

    func testOpen_browseItem_callsOpenEntryOnce() async {
        await sut.open(browseItem())

        XCTAssertEqual(mockOpenEntry.callCount, 1)
    }

    func testOpen_browseItem_passesEntryToUseCase() async {
        let item = browseItem()
        await sut.open(item)

        XCTAssertEqual(mockOpenEntry.receivedRequest?.entry, item)
    }

    func testOpen_commandItem_callsOpenEntryOnce() async {
        await sut.open(commandItem())

        XCTAssertEqual(mockOpenEntry.callCount, 1)
    }

    func testOpen_commandItem_passesName() async {
        let command = CommandPayload(commandLine: "/bin/ls", workingDirectory: nil, sink: .background)
        await sut.open(ItemFixtures.make(name: "List", kind: .command(command)))

        XCTAssertEqual(mockOpenEntry.receivedRequest?.entry.name, "List")
    }

    func testOpen_commandItem_passesCommandPayload() async {
        let command = CommandPayload(commandLine: "/bin/ls", workingDirectory: nil, sink: .background)
        await sut.open(ItemFixtures.make(name: "List", kind: .command(command)))

        XCTAssertEqual(mockOpenEntry.receivedRequest?.entry.kind, .command(command))
    }
}
