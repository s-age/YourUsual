import Foundation
@testable import YourUsual

// MARK: - Shared call-counting mocks for the UseCase layer

final class MockSavedEntryService: SavedEntryServiceProtocol, @unchecked Sendable {
    // The pure transforms carry no I/O, so the mock delegates them to a real
    // SavedEntryService (its repository is never touched by a transform). This
    // keeps the orchestration tests honest about the actual rule output while
    // still letting them count listAll() and stub its result.
    private let transforms = SavedEntryService(repository: NoopSavedEntryRepository())

    // listAll()
    var listAllCallCount = 0
    var listAllResult: [SavedEntry] = []
    var listAllError: Error?   // when set, listAll() throws it (default nil = succeeds)

    func listAll() throws -> [SavedEntry] {
        listAllCallCount += 1
        if let listAllError { throw listAllError }
        return listAllResult
    }

    var healingRecoveredCallCount = 0
    func healingRecovered(_ current: [SavedEntry]) -> (items: [SavedEntry], healedCount: Int)? {
        healingRecoveredCallCount += 1
        return transforms.healingRecovered(current)
    }

    var registeringCallCount = 0
    func registering(
        _ current: [SavedEntry], name: String, kind: EntryKind, categoryID: UUID?
    ) -> (items: [SavedEntry], registered: SavedEntry) {
        registeringCallCount += 1
        return transforms.registering(current, name: name, kind: kind, categoryID: categoryID)
    }

    var editingCallCount = 0
    func editing(
        _ current: [SavedEntry], id: UUID, edit: SavedEntryEdit
    ) throws -> (items: [SavedEntry], edited: SavedEntry) {
        editingCallCount += 1
        return try transforms.editing(current, id: id, edit: edit)
    }

    var reorderingCallCount = 0
    func reordering(_ current: [SavedEntry], orderedIDs: [UUID]) -> [SavedEntry]? {
        reorderingCallCount += 1
        return transforms.reordering(current, orderedIDs: orderedIDs)
    }

    var movingCallCount = 0
    func moving(
        _ current: [SavedEntry], id: UUID, toCategory categoryID: UUID,
        knownCategoryIDs: Set<UUID>
    ) throws -> [SavedEntry]? {
        movingCallCount += 1
        return try transforms.moving(
            current, id: id, toCategory: categoryID, knownCategoryIDs: knownCategoryIDs
        )
    }

    var deletingCallCount = 0
    func deleting(_ current: [SavedEntry], id: UUID) throws -> [SavedEntry] {
        deletingCallCount += 1
        return try transforms.deleting(current, id: id)
    }

    var editingSliderValueCallCount = 0
    var editingSliderValueID: UUID?
    var editingSliderValueValue: Double?
    func editingSliderValue(_ current: [SavedEntry], id: UUID, value: Double) -> [SavedEntry] {
        editingSliderValueCallCount += 1
        editingSliderValueID = id
        editingSliderValueValue = value
        return transforms.editingSliderValue(current, id: id, value: value)
    }
}

private struct NoopSavedEntryRepository: SavedEntryRepositoryProtocol, @unchecked Sendable {
    func listAll() async throws -> [SavedEntry] { [] }
}

final class MockCategoryService: CategoryServiceProtocol, @unchecked Sendable {
    // Mirrors MockSavedEntryService: pure transforms delegate to a real CategoryService
    // (its repository is never touched by a transform), while listAll() is stubbed/counted.
    private let transforms = CategoryService(repository: NoopCategoryRepository())

    var listAllCallCount = 0
    var listAllResult: [EntryCategory] = []

    func listAll() throws -> [EntryCategory] {
        listAllCallCount += 1
        return listAllResult
    }

    func ensuringDefault(_ current: [EntryCategory]) -> [EntryCategory]? {
        transforms.ensuringDefault(current)
    }

    func registering(_ current: [EntryCategory], name: String)
        -> (categories: [EntryCategory], registered: EntryCategory) {
        transforms.registering(current, name: name)
    }

    func reordering(_ current: [EntryCategory], orderedIDs: [UUID]) -> [EntryCategory]? {
        transforms.reordering(current, orderedIDs: orderedIDs)
    }

    func editing(
        _ current: [EntryCategory], id: UUID, name: String, isHiddenFromMenuBar: Bool
    ) throws -> [EntryCategory] {
        try transforms.editing(current, id: id, name: name, isHiddenFromMenuBar: isHiddenFromMenuBar)
    }

    func deleting(_ current: [EntryCategory], id: UUID) throws -> [EntryCategory] {
        try transforms.deleting(current, id: id)
    }
}

private struct NoopCategoryRepository: CategoryRepositoryProtocol, @unchecked Sendable {
    func listAll() async throws -> [EntryCategory] { [] }
}

final class MockCommandOutputSettingsService: CommandOutputSettingsServiceProtocol, @unchecked Sendable {
    var currentResult = CommandOutputPreference.default
    var currentCallCount = 0
    var setBufferLinesCallCount = 0
    var lastSetBufferLines: Int?

    func current() -> CommandOutputPreference {
        currentCallCount += 1
        return currentResult
    }

    func setBufferLines(_ lines: Int) -> CommandOutputPreference {
        setBufferLinesCallCount += 1
        lastSetBufferLines = lines
        currentResult = CommandOutputPreference(bufferLines: lines)
        return currentResult
    }
}

// MARK: - Behaviour service mocks

final class MockBrowseLauncherService: BrowseLauncherServiceProtocol, @unchecked Sendable {
    var launchCallCount = 0
    var launchedEntry: BrowseEntry?
    var error: Error?

    func launch(_ entry: BrowseEntry) async throws {
        launchCallCount += 1
        launchedEntry = entry
        if let error { throw error }
    }
}

final class MockCommandRunnerService: CommandRunnerServiceProtocol, @unchecked Sendable {
    var performCallCount = 0
    var performedEntry: CommandEntry?
    var performedPreference: TerminalPreference?
    var performedCurrentDirectory: URL?
    var error: Error?

    func perform(_ entry: CommandEntry, preference: TerminalPreference, currentDirectory: URL) async throws {
        performCallCount += 1
        performedEntry = entry
        performedPreference = preference
        performedCurrentDirectory = currentDirectory
        if let error { throw error }
    }

    var streamCallCount = 0
    var streamedEntry: CommandEntry?
    var streamedCurrentDirectory: URL?
    var streamEvents: [CommandOutputEvent] = []
    var streamError: Error?

    func stream(_ entry: CommandEntry, currentDirectory: URL) -> any AsyncSequence<CommandOutputEvent, Error> {
        streamCallCount += 1
        streamedEntry = entry
        streamedCurrentDirectory = currentDirectory
        let events = streamEvents
        let error = streamError
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            if let error { continuation.finish(throwing: error) } else { continuation.finish() }
        }
    }
}

final class MockCurrentDirectoryService: CurrentDirectoryServiceProtocol, @unchecked Sendable {
    var preference: CurrentDirectoryPreference = .default
    var setPathCallCount = 0
    var setPathValues: [String?] = []
    var setPathError: Error?

    func current() -> CurrentDirectoryPreference { preference }
    func setPath(_ path: String?) throws {
        setPathCallCount += 1
        setPathValues.append(path)
        if let setPathError { throw setPathError }
        preference = CurrentDirectoryPreference(path: path)
    }
}

final class MockWorkingDirectoryResolver: WorkingDirectoryResolverProtocol, @unchecked Sendable {
    var resolveResult = URL(fileURLWithPath: "/home/user")
    var resolvedInputs: [String?] = []

    func resolve(_ path: String?) -> URL {
        resolvedInputs.append(path)
        return resolveResult
    }
}

final class MockAppleScriptRunnerService: AppleScriptRunnerServiceProtocol, @unchecked Sendable {
    var runCallCount = 0
    var ranEntry: AppleScriptEntry?
    var runResult: String?
    var error: Error?

    func run(_ entry: AppleScriptEntry) async throws -> String? {
        runCallCount += 1
        ranEntry = entry
        if let error { throw error }
        return runResult
    }
}

final class MockTerminalSettingsService: TerminalSettingsServiceProtocol, @unchecked Sendable {
    var currentResult = TerminalPreference.default
    var currentCallCount = 0

    func current() -> TerminalPreference {
        currentCallCount += 1
        return currentResult
    }

    func availableTerminals() -> [TerminalAppSelection] { [.known(.terminal)] }

    func setPreference(selection: TerminalAppSelection, launchMode: TerminalLaunchMode) throws
        -> TerminalPreference {
        TerminalPreference(selection: selection, launchMode: launchMode)
    }

    func resolveApp(at url: URL) -> TerminalAppSelection? { nil }
    func normalizeStoredPreference() throws -> Bool { false }
}

final class MockNotificationService: NotificationServiceProtocol, @unchecked Sendable {
    var notifyIfNeededCallCount = 0
    var notifiedName: String?
    var notifiedResult: CommandResult?

    func notifyIfNeeded(name: String, result: CommandResult?) async {
        notifyIfNeededCallCount += 1
        notifiedName = name
        notifiedResult = result
    }

    var notifyCompletionCallCount = 0
    var completedName: String?

    func notifyCompletion(name: String) async {
        notifyCompletionCallCount += 1
        completedName = name
    }

    var notifyFailureCallCount = 0
    var failedName: String?
    var failedMessage: String?

    func notifyFailure(name: String, error: any Error) async {
        notifyFailureCallCount += 1
        failedName = name
        failedMessage = error.localizedDescription
    }
}

// MARK: - Diagnostics port mock

final class MockDiagnostics: DiagnosticsLoggingProtocol, @unchecked Sendable {
    var warningCallCount = 0
    var warnings: [String] = []

    func warning(_ message: String) {
        warningCallCount += 1
        warnings.append(message)
    }
}

// MARK: - History service mock

final class MockRunHistoryService: RunHistoryServiceProtocol, @unchecked Sendable {
    var listForEntryCallCount = 0
    var listForEntryID: UUID?
    var listForEntryResult: [RunRecord] = []

    var listAllCallCount = 0
    var listAllResult: [RunRecord] = []

    func list(forEntry id: UUID) async throws -> [RunRecord] {
        listForEntryCallCount += 1
        listForEntryID = id
        return listForEntryResult
    }

    func listAll() async throws -> [RunRecord] {
        listAllCallCount += 1
        return listAllResult
    }

    var makeRunRecordCallCount = 0
    func makeRunRecord(
        forEntry entryID: UUID, named entryName: String,
        command: CommandEntry, result: CommandResult
    ) -> RunRecord {
        makeRunRecordCallCount += 1
        return RunRecord.command(
            entryID: entryID,
            entryName: entryName,
            executedAt: Date(timeIntervalSince1970: 0),
            outcome: CommandRunOutcome(commandLine: command.line, result: result)
        )
    }
}
