import Foundation

/// Base contract for asynchronous use cases (I/O, persistence).
///
/// Concrete use cases conform to this directly; each use case's public
/// contract is exposed as a `typealias` over `any AsyncUseCase<Request, Response>`.
protocol AsyncUseCase<Request, Response>: Sendable {
    associatedtype Request
    associatedtype Response
    func execute(_ request: Request) async throws -> Response
}

/// Base contract for synchronous use cases (pure computation, no I/O).
///
/// Concrete use cases conform to this directly; each use case's public
/// contract is exposed as a `typealias` over `any SyncUseCase<Request, Response>`.
protocol SyncUseCase<Request, Response>: Sendable {
    associatedtype Request
    associatedtype Response
    func execute(_ request: Request) throws -> Response
}

typealias DeleteCategoryUseCaseProtocol = any AsyncUseCase<DeleteCategoryRequest, Void>
typealias EditCategoryUseCaseProtocol = any AsyncUseCase<EditCategoryRequest, Void>
typealias DeleteEntryUseCaseProtocol = any AsyncUseCase<DeleteEntryRequest, Void>
typealias DeleteHistoryUseCaseProtocol = any AsyncUseCase<DeleteHistoryRequest, Void>
typealias EditEntryUseCaseProtocol = any AsyncUseCase<EditEntryRequest, SavedEntryResponse>
typealias EnsureDefaultCategoryUseCaseProtocol = any AsyncUseCase<EnsureDefaultCategoryRequest, Void>
typealias HealRecoveredEntriesUseCaseProtocol = any AsyncUseCase<HealRecoveredEntriesRequest, Int>
typealias ReadCommandOutputSettingsUseCaseProtocol =
    any SyncUseCase<ReadCommandOutputSettingsRequest, CommandOutputSettingsResponse>
typealias SetCommandOutputBufferUseCaseProtocol =
    any SyncUseCase<SetCommandOutputBufferRequest, CommandOutputSettingsResponse>
typealias MigrateLegacyRegistryUseCaseProtocol = any AsyncUseCase<MigrateLegacyRegistryRequest, Void>
typealias OpenEntryUseCaseProtocol = any AsyncUseCase<OpenEntryRequest, Void>
typealias ReadCategoriesUseCaseProtocol = any AsyncUseCase<ReadCategoriesRequest, [CategoryResponse]>
typealias ReadEntriesUseCaseProtocol = any AsyncUseCase<ReadEntriesRequest, [SavedEntryResponse]>
typealias ReadHistoryUseCaseProtocol = any AsyncUseCase<ReadHistoryRequest, [RunHistoryResponse]>
typealias ReadLaunchAtLoginUseCaseProtocol = any SyncUseCase<ReadLaunchAtLoginRequest, Bool>
typealias ReadTerminalSettingsUseCaseProtocol =
    any SyncUseCase<ReadTerminalSettingsRequest, TerminalSettingsResponse>
typealias NormalizeTerminalPreferenceUseCaseProtocol =
    any SyncUseCase<NormalizeTerminalPreferenceRequest, Void>
typealias RegisterCategoryUseCaseProtocol = any AsyncUseCase<RegisterCategoryRequest, CategoryResponse>
typealias ReorderCategoriesUseCaseProtocol = any AsyncUseCase<ReorderCategoriesRequest, Void>
typealias RegisterEntryUseCaseProtocol = any AsyncUseCase<RegisterEntryRequest, SavedEntryResponse>
typealias ReorderEntriesUseCaseProtocol = any AsyncUseCase<ReorderEntriesRequest, Void>
typealias MoveEntryToCategoryUseCaseProtocol = any AsyncUseCase<MoveEntryToCategoryRequest, Void>
typealias ResolveAppBundleIdentifierUseCaseProtocol =
    any SyncUseCase<ResolveAppBundleIdentifierRequest, String?>
typealias ResolveAppIconUseCaseProtocol =
    any AsyncUseCase<ResolveAppIconRequest, URL?>
typealias ResolveTerminalAppUseCaseProtocol =
    any SyncUseCase<ResolveTerminalAppRequest, TerminalAppOptionResponse?>
typealias ResolveWorkingDirectoryUseCaseProtocol =
    any SyncUseCase<ResolveWorkingDirectoryRequest, String>
typealias ReadCurrentDirectoryUseCaseProtocol =
    any SyncUseCase<ReadCurrentDirectoryRequest, CurrentDirectoryResponse>
typealias SetCurrentDirectoryUseCaseProtocol =
    any SyncUseCase<SetCurrentDirectoryRequest, CurrentDirectoryResponse>
typealias RunStreamingEntryUseCaseProtocol =
    any AsyncUseCase<RunStreamingEntryRequest, AsyncThrowingStream<CommandOutputResponse, Error>>
typealias RunSliderUseCaseProtocol = any AsyncUseCase<RunSliderRequest, Void>
typealias SetSliderValueUseCaseProtocol = any AsyncUseCase<SetSliderValueRequest, Void>
typealias SetLaunchAtLoginUseCaseProtocol = any SyncUseCase<SetLaunchAtLoginRequest, Bool>
typealias SetTerminalPreferenceUseCaseProtocol =
    any SyncUseCase<SetTerminalPreferenceRequest, TerminalSettingsResponse>
typealias ReadPadLayoutsUseCaseProtocol     = any AsyncUseCase<ReadPadLayoutsRequest, PadLayoutsResponse>
typealias RegisterPadLayoutUseCaseProtocol  = any AsyncUseCase<RegisterPadLayoutRequest, PadLayoutResponse>
typealias EditPadLayoutUseCaseProtocol      = any AsyncUseCase<EditPadLayoutRequest, PadLayoutResponse>
typealias DeletePadLayoutUseCaseProtocol    = any AsyncUseCase<DeletePadLayoutRequest, Void>
typealias ReorderPadLayoutsUseCaseProtocol  = any AsyncUseCase<ReorderPadLayoutsRequest, Void>
typealias SavePadCellUseCaseProtocol        = any AsyncUseCase<SavePadCellRequest, Void>
typealias DeletePadCellUseCaseProtocol      = any AsyncUseCase<DeletePadCellRequest, Void>
typealias ProbeIconImageUseCaseProtocol     = any AsyncUseCase<ProbeIconImageRequest, IconImageSizeResponse>
