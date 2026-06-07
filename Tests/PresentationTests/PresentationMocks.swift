import Foundation
@testable import YourUsual

// MARK: - Shared call-counting mocks for the Presentation layer
//
// These mock the UseCase protocols consumed by the ViewModels. Mutation is driven
// exclusively by test setup, so `@unchecked Sendable` is acceptable here.

final class MockReadEntriesUseCase: AsyncUseCase, @unchecked Sendable {
    var callCount = 0
    var result: [SavedEntryResponse] = []
    var error: Error?
    /// Invoked on the main actor while `execute` is in flight — lets tests observe
    /// transient ViewModel state during the await.
    var onExecute: (@MainActor () -> Void)?

    func execute(_ request: ReadEntriesRequest) async throws -> [SavedEntryResponse] {
        callCount += 1
        await onExecute?()
        if let error { throw error }
        return result
    }
}

final class MockReadCategoriesUseCase: AsyncUseCase, @unchecked Sendable {
    var callCount = 0
    var result: [CategoryResponse] = []
    var error: Error?

    func execute(_ request: ReadCategoriesRequest) async throws -> [CategoryResponse] {
        callCount += 1
        if let error { throw error }
        return result
    }
}

final class MockOpenEntryUseCase: AsyncUseCase, @unchecked Sendable {
    var callCount = 0
    var receivedRequest: OpenEntryRequest?
    var error: Error?

    func execute(_ request: OpenEntryRequest) async throws {
        callCount += 1
        receivedRequest = request
        if let error { throw error }
    }
}

final class MockRunStreamingEntryUseCase: AsyncUseCase, @unchecked Sendable {
    var callCount = 0
    var receivedRequest: RunStreamingEntryRequest?
    var events: [CommandOutputResponse] = []
    /// When true the returned stream yields `events` but never finishes, so the
    /// consumer suspends on the open stream. Lets a test interleave a cancel and an
    /// immediate re-run before the first run ends (the delete-then-rerun race). The
    /// suspended consumer still resumes when its task is cancelled.
    var keepOpen = false

    func execute(
        _ request: RunStreamingEntryRequest
    ) async throws -> AsyncThrowingStream<CommandOutputResponse, Error> {
        callCount += 1
        receivedRequest = request
        let events = self.events
        let keepOpen = self.keepOpen
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            if !keepOpen { continuation.finish() }
        }
    }
}

final class MockDeleteEntryUseCase: AsyncUseCase, @unchecked Sendable {
    var callCount = 0
    var deletedID: UUID?
    var error: Error?

    func execute(_ request: DeleteEntryRequest) async throws {
        callCount += 1
        deletedID = request.id
        if let error { throw error }
    }
}

final class MockReorderEntriesUseCase: AsyncUseCase, @unchecked Sendable {
    var callCount = 0
    var orderedIDs: [UUID]?
    var error: Error?

    func execute(_ request: ReorderEntriesRequest) async throws {
        callCount += 1
        orderedIDs = request.orderedIDs
        if let error { throw error }
    }
}

final class MockMoveEntryToCategoryUseCase: AsyncUseCase, @unchecked Sendable {
    var callCount = 0
    var receivedRequest: MoveEntryToCategoryRequest?
    var error: Error?

    func execute(_ request: MoveEntryToCategoryRequest) async throws {
        callCount += 1
        receivedRequest = request
        if let error { throw error }
    }
}

final class MockRegisterEntryUseCase: AsyncUseCase, @unchecked Sendable {
    var callCount = 0
    var receivedRequest: RegisterEntryRequest?
    var error: Error?
    var result = SavedEntryResponse(
        id: UUID(),
        name: "stub",
        kind: .browse(BrowsePayload(path: "/tmp/stub", app: .default))
    )

    func execute(_ request: RegisterEntryRequest) async throws -> SavedEntryResponse {
        callCount += 1
        receivedRequest = request
        if let error { throw error }
        return result
    }
}

final class MockEditEntryUseCase: AsyncUseCase, @unchecked Sendable {
    var callCount = 0
    var receivedRequest: EditEntryRequest?
    var error: Error?
    var result = SavedEntryResponse(
        id: UUID(),
        name: "stub",
        kind: .browse(BrowsePayload(path: "/tmp/stub", app: .default))
    )

    func execute(_ request: EditEntryRequest) async throws -> SavedEntryResponse {
        callCount += 1
        receivedRequest = request
        if let error { throw error }
        return result
    }
}

final class MockReadLaunchAtLoginUseCase: SyncUseCase, @unchecked Sendable {
    var callCount = 0
    var result = false
    var error: Error?

    func execute(_ request: ReadLaunchAtLoginRequest) throws -> Bool {
        callCount += 1
        if let error { throw error }
        return result
    }
}

final class MockSetLaunchAtLoginUseCase: SyncUseCase, @unchecked Sendable {
    var callCount = 0
    var receivedEnabled: Bool?
    /// State the toggle "applies" — returned from `execute` to mirror the system result.
    var result = false
    var error: Error?

    func execute(_ request: SetLaunchAtLoginRequest) throws -> Bool {
        callCount += 1
        receivedEnabled = request.enabled
        if let error { throw error }
        return result
    }
}

final class MockReadCurrentDirectoryUseCase: SyncUseCase, @unchecked Sendable {
    var callCount = 0
    var result = CurrentDirectoryResponse(path: "/home/user")
    var error: Error?

    func execute(_ request: ReadCurrentDirectoryRequest) throws -> CurrentDirectoryResponse {
        callCount += 1
        if let error { throw error }
        return result
    }
}

final class MockSetCurrentDirectoryUseCase: SyncUseCase, @unchecked Sendable {
    var callCount = 0
    var receivedPath: String??
    var result = CurrentDirectoryResponse(path: "/home/user")
    var error: Error?

    func execute(_ request: SetCurrentDirectoryRequest) throws -> CurrentDirectoryResponse {
        callCount += 1
        receivedPath = request.path
        if let error { throw error }
        return result
    }
}

// MARK: - AppIconCache test helper

/// Stub resolver — never resolves an icon (returns nil) so the shared `AppIconCache` that
/// every entry-listing ViewModel now requires can be constructed in headless tests without
/// touching `NSWorkspace`.
final class MockResolveAppIconUseCase: AsyncUseCase, @unchecked Sendable {
    func execute(_ request: ResolveAppIconRequest) async throws -> URL? { nil }
}

@MainActor
func makeTestAppIconCache() -> AppIconCache {
    AppIconCache(resolveAppIcon: MockResolveAppIconUseCase())
}

// MARK: - Fixtures

enum ItemFixtures {
    static func make(
        id: UUID = UUID(),
        name: String = "Item",
        kind: EntryKindPayload = .browse(BrowsePayload(path: "/tmp/file.txt", app: .default)),
        categoryID: UUID = EntryCategory.defaultID,
        isRecovered: Bool = false,
        isHiddenFromMenuBar: Bool = false
    ) -> SavedEntryResponse {
        SavedEntryResponse(
            id: id, name: name, kind: kind, categoryID: categoryID,
            isRecovered: isRecovered, isHiddenFromMenuBar: isHiddenFromMenuBar
        )
    }
}
