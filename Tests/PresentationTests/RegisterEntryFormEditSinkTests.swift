import SwiftData
import XCTest
@testable import YourUsual

/// End-to-end editing path for a command's Action (background ↔ terminal),
/// driving the REAL form ViewModel → EditEntryUseCase → SavedEntryService →
/// SavedEntryRepository → RegistryDatabase (in-memory), then reloading.
/// Mirrors exactly what the user does in the settings form.
@MainActor
final class RegisterEntryFormEditSinkTests: XCTestCase {
    private var repository: SavedEntryRepository!
    private var register: RegisterEntryUseCase!
    private var edit: EditEntryUseCase!

    private struct StubResolveWorkingDirectory: SyncUseCase, @unchecked Sendable {
        func execute(_ request: ResolveWorkingDirectoryRequest) throws -> String {
            request.path ?? "/Users/test"
        }
    }

    private struct StubResolveAppBundleIdentifier: SyncUseCase, @unchecked Sendable {
        func execute(_ request: ResolveAppBundleIdentifierRequest) throws -> String? {
            "com.example.app"
        }
    }

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: EntryModel.self, CommandRunModel.self, CategoryModel.self,
            BrowseEntryModel.self, CommandEntryModel.self, AppleScriptEntryModel.self,
            configurations: config
        )
        let db = RegistryDatabase(modelContainer: container)
        repository = SavedEntryRepository(store: db, logger: MockDiagnosticsLogger())
        let service = SavedEntryService(repository: repository)
        let gateway = RegistryDatabaseGateway(runner: db)
        register = RegisterEntryUseCase(entries: service, db: gateway)
        edit = EditEntryUseCase(entries: service, db: gateway)
    }

    override func tearDown() {
        repository = nil
        register = nil
        edit = nil
        super.tearDown()
    }

    private func makeForm(editing: SavedEntryResponse?) -> RegisterEntryFormViewModel {
        RegisterEntryFormViewModel(
            editing: editing,
            categoryID: EntryCategory.defaultID,
            register: register,
            edit: edit,
            resolveWorkingDirectory: StubResolveWorkingDirectory(),
            resolveAppBundleIdentifier: StubResolveAppBundleIdentifier(),
            registry: RegistryViewModel(
                readEntries: MockReadEntriesUseCase(),
                readCategories: MockReadCategoriesUseCase()
            )
        )
    }

    private func reloadSink(id: UUID) async throws -> CommandSink? {
        let items = try await repository.listAll()
        guard case .command(let command) = items.first(where: { $0.id == id })?.kind else { return nil }
        return command.sink
    }

    func test_editForm_changesSink_backgroundToTerminal_persists() async throws {
        // Register a background command via the real register use case.
        let created = try await register.execute(RegisterEntryRequest(
            name: "Cmd",
            kind: .command(CommandPayload(commandLine: "echo hi", workingDirectory: nil, sink: .background)),
            categoryID: EntryCategory.defaultID
        ))

        // Open the edit form for it — prefill must reflect .background.
        let form = makeForm(editing: created)
        XCTAssertEqual(form.commandForm.handlerKind, .background)

        // User flips the Action picker to terminal and saves.
        form.commandForm.handlerKind = .terminal
        let ok = await form.submit()
        XCTAssertTrue(ok)

        let sink = try await reloadSink(id: created.id)
        XCTAssertEqual(sink, .terminal)
    }

    /// Reproduces the live-UI bug: SwiftUI's Type Picker can write the SAME
    /// `entryKind` value back during a re-render. Now that the command's Action
    /// lives in a dedicated child ViewModel, the parent's `entryKind` no longer
    /// reaches into it — re-writing the Type can't clobber `handlerKind`.
    func test_settingEntryKindToSameValue_doesNotResetHandlerKind() async throws {
        let created = try await register.execute(RegisterEntryRequest(
            name: "Cmd",
            kind: .command(CommandPayload(commandLine: "echo hi", workingDirectory: nil, sink: .terminal)),
            categoryID: EntryCategory.defaultID
        ))
        let form = makeForm(editing: created)
        XCTAssertEqual(form.commandForm.handlerKind, .terminal)

        form.entryKind = .command   // unchanged value, as SwiftUI may re-write

        XCTAssertEqual(form.commandForm.handlerKind, .terminal)
    }

    func test_editForm_changesSink_terminalToBackground_persists() async throws {
        let created = try await register.execute(RegisterEntryRequest(
            name: "Cmd",
            kind: .command(CommandPayload(commandLine: "echo hi", workingDirectory: nil, sink: .terminal)),
            categoryID: EntryCategory.defaultID
        ))

        let form = makeForm(editing: created)
        XCTAssertEqual(form.commandForm.handlerKind, .terminal)

        form.commandForm.handlerKind = .background
        let ok = await form.submit()
        XCTAssertTrue(ok)

        let sink = try await reloadSink(id: created.id)
        XCTAssertEqual(sink, .background)
    }
}
