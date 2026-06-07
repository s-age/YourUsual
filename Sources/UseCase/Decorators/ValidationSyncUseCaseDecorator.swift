import Foundation

/// Synchronous counterpart to `ValidationAsyncUseCaseDecorator`: runs
/// `request.validate()` before delegating to a sync use case. Wraps a
/// `SyncUseCase` and conforms to `SyncUseCase`, preserving the typealias surface.
/// `Request` is constrained to `ValidatableRequest` for the same reason as the
/// async decorator — a non-validating request cannot be wrapped.
final class ValidationSyncUseCaseDecorator<Request: ValidatableRequest, Response>: SyncUseCase, Sendable {
    private let decoratee: any SyncUseCase<Request, Response>

    init(decoratee: any SyncUseCase<Request, Response>) {
        self.decoratee = decoratee
    }

    func execute(_ request: Request) throws -> Response {
        try request.validate()
        return try decoratee.execute(request)
    }
}
