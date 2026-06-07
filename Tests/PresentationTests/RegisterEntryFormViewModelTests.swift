import XCTest
@testable import YourUsual

private struct StubResolveWorkingDirectory: SyncUseCase {
    func execute(_ request: ResolveWorkingDirectoryRequest) throws -> String {
        "/Users/test"
    }
}

private struct StubResolveAppBundleIdentifier: SyncUseCase {
    func execute(_ request: ResolveAppBundleIdentifierRequest) throws -> String? {
        "com.example.app"
    }
}

@MainActor
final class RegisterEntryFormViewModelTests: XCTestCase {
    private var mockRegister: MockRegisterEntryUseCase!
    private var mockEdit: MockEditEntryUseCase!

    override func setUp() {
        super.setUp()
        mockRegister = MockRegisterEntryUseCase()
        mockEdit = MockEditEntryUseCase()
    }

    override func tearDown() {
        mockRegister = nil
        mockEdit = nil
        super.tearDown()
    }

    private func makeSUT(editing: SavedEntryResponse?) -> RegisterEntryFormViewModel {
        RegisterEntryFormViewModel(
            editing: editing,
            categoryID: nil,
            register: mockRegister,
            edit: mockEdit,
            resolveWorkingDirectory: StubResolveWorkingDirectory(),
            resolveAppBundleIdentifier: StubResolveAppBundleIdentifier(),
            registry: RegistryViewModel(
                readEntries: MockReadEntriesUseCase(),
                readCategories: MockReadCategoriesUseCase()
            )
        )
    }

    /// A valid editable item: browse entry opened with the default app.
    private func validEditItem() -> SavedEntryResponse {
        ItemFixtures.make(name: "My File", kind: .browse(BrowsePayload(path: "/tmp/file.txt", app: .default)))
    }

    // MARK: - Menu-bar visibility toggle

    func test_isEditing_trueWhenEditing() {
        XCTAssertTrue(makeSUT(editing: validEditItem()).isEditing)
    }

    func test_isEditing_falseWhenAdding() {
        XCTAssertFalse(makeSUT(editing: nil).isEditing)
    }

    func test_showsInMenuBar_prefillsFromVisibleEntry() {
        let item = ItemFixtures.make(isHiddenFromMenuBar: false)
        XCTAssertTrue(makeSUT(editing: item).showsInMenuBar)
    }

    func test_showsInMenuBar_prefillsFromHiddenEntry() {
        let item = ItemFixtures.make(isHiddenFromMenuBar: true)
        XCTAssertFalse(makeSUT(editing: item).showsInMenuBar)
    }

    func test_togglingShowsInMenuBar_makesFormDirty() {
        let sut = makeSUT(editing: validEditItem())
        XCTAssertFalse(sut.isDirty)
        sut.showsInMenuBar.toggle()
        XCTAssertTrue(sut.isDirty)
    }

    func testSubmit_editHidingEntry_passesIsHiddenTrue() async {
        let sut = makeSUT(editing: ItemFixtures.make(isHiddenFromMenuBar: false))
        sut.showsInMenuBar = false
        _ = await sut.submit()
        XCTAssertEqual(mockEdit.receivedRequest?.isHiddenFromMenuBar, true)
    }

    func testSubmit_editKeepingVisible_passesIsHiddenFalse() async {
        let sut = makeSUT(editing: validEditItem())
        // Make a different change so the form is dirty without touching visibility.
        sut.name = "Renamed"
        _ = await sut.submit()
        XCTAssertEqual(mockEdit.receivedRequest?.isHiddenFromMenuBar, false)
    }

    // MARK: - submit() — valid edit

    func testSubmit_validEdit_callsEditOnce() async {
        let sut = makeSUT(editing: validEditItem())

        _ = await sut.submit()

        XCTAssertEqual(mockEdit.callCount, 1)
    }

    func testSubmit_validEdit_doesNotCallRegister() async {
        let sut = makeSUT(editing: validEditItem())

        _ = await sut.submit()

        XCTAssertEqual(mockRegister.callCount, 0)
    }

    func testSubmit_validEdit_returnsTrue() async {
        let sut = makeSUT(editing: validEditItem())

        let result = await sut.submit()

        XCTAssertTrue(result)
    }

    func testSubmit_validEdit_updatesMatchingID() async {
        let item = validEditItem()
        let sut = makeSUT(editing: item)

        _ = await sut.submit()

        XCTAssertEqual(mockEdit.receivedRequest?.id, item.id)
    }

    func testSubmit_validEdit_clearsValidationMessage() async {
        let sut = makeSUT(editing: validEditItem())

        _ = await sut.submit()

        XCTAssertNil(sut.validationMessage)
    }

    // MARK: - submit() — OperationError

    func testSubmit_domainError_returnsFalse() async {
        mockEdit.error = OperationError.invalidItem(reason: "name is empty")
        let sut = makeSUT(editing: validEditItem())

        let result = await sut.submit()

        XCTAssertFalse(result)
    }

    func testSubmit_domainError_setsValidationMessage() async {
        mockEdit.error = OperationError.invalidItem(reason: "name is empty")
        let sut = makeSUT(editing: validEditItem())

        _ = await sut.submit()

        XCTAssertEqual(sut.validationMessage, "Invalid item: name is empty")
    }

    // MARK: - submit() — ValidationError

    func testSubmit_validationError_returnsFalse() async {
        mockEdit.error = ValidationError.emptyField(name: "name")
        let sut = makeSUT(editing: validEditItem())

        let result = await sut.submit()

        XCTAssertFalse(result)
    }

    func testSubmit_validationError_setsValidationMessage() async {
        mockEdit.error = ValidationError.emptyField(name: "name")
        let sut = makeSUT(editing: validEditItem())

        _ = await sut.submit()

        XCTAssertEqual(sut.validationMessage, "name is empty")
    }

    // MARK: - submit() — isSaving lifecycle

    func testSubmit_isSavingFalseAfterSuccess() async {
        let sut = makeSUT(editing: validEditItem())

        _ = await sut.submit()

        XCTAssertFalse(sut.isSaving)
    }

    func testSubmit_isSavingFalseAfterFailure() async {
        mockEdit.error = OperationError.invalidItem(reason: "name is empty")
        let sut = makeSUT(editing: validEditItem())

        _ = await sut.submit()

        XCTAssertFalse(sut.isSaving)
    }

    // MARK: - submit() — new registration (editing == nil)

    func testSubmit_validNew_callsRegisterOnce() async {
        let sut = makeSUT(editing: nil)
        sut.name = "New File"
        sut.entryKind = .browse
        sut.browseForm.path = "/tmp/new.txt"

        _ = await sut.submit()

        XCTAssertEqual(mockRegister.callCount, 1)
    }

    func testSubmit_validNew_doesNotCallEdit() async {
        let sut = makeSUT(editing: nil)
        sut.name = "New File"
        sut.entryKind = .browse
        sut.browseForm.path = "/tmp/new.txt"

        _ = await sut.submit()

        XCTAssertEqual(mockEdit.callCount, 0)
    }

    // MARK: - isDirty

    func testIsDirty_newForm_falseBeforeAnyEdit() {
        let sut = makeSUT(editing: nil)

        XCTAssertFalse(sut.isDirty)
    }

    func testIsDirty_newForm_trueAfterNameChange() {
        let sut = makeSUT(editing: nil)

        sut.name = "Something"

        XCTAssertTrue(sut.isDirty)
    }

    func testIsDirty_newForm_trueAfterFieldChange() {
        let sut = makeSUT(editing: nil)

        sut.browseForm.path = "/tmp/new.txt"

        XCTAssertTrue(sut.isDirty)
    }

    func testIsDirty_editForm_falseBeforeAnyEdit() {
        let sut = makeSUT(editing: validEditItem())

        XCTAssertFalse(sut.isDirty)
    }

    func testIsDirty_editForm_trueAfterNameChange() {
        let sut = makeSUT(editing: validEditItem())

        sut.name = "Renamed"

        XCTAssertTrue(sut.isDirty)
    }

    // MARK: - isEditingRecovered

    func testIsEditingRecovered_editingRecoveredItem_isTrue() {
        let recovered = ItemFixtures.make(
            kind: .browse(BrowsePayload(path: "/tmp/file.txt", app: .default)), isRecovered: true
        )
        let sut = makeSUT(editing: recovered)

        XCTAssertTrue(sut.isEditingRecovered)
    }

    func testIsEditingRecovered_editingNormalItem_isFalse() {
        let sut = makeSUT(editing: validEditItem())

        XCTAssertFalse(sut.isEditingRecovered)
    }

    func testIsEditingRecovered_newForm_isFalse() {
        let sut = makeSUT(editing: nil)

        XCTAssertFalse(sut.isEditingRecovered)
    }

    // MARK: - title

    func testTitle_newForm_isNewItem() {
        let sut = makeSUT(editing: nil)

        XCTAssertEqual(sut.title, "New Item")
    }

    func testTitle_editForm_isEditItem() {
        let sut = makeSUT(editing: validEditItem())

        XCTAssertEqual(sut.title, "Edit Item")
    }
}
