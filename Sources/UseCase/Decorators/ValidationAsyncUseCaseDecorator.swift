import Foundation

/// Wraps an async use case and runs `request.validate()` before delegating, so
/// input validation is a cross-cutting concern applied in the DI layer rather
/// than open-coded in every concrete use case.
///
/// Conforms to `AsyncUseCase` itself, so the wrapped use case keeps the same
/// `*UseCaseProtocol` typealias surface the Presentation layer consumes.
///
/// `Request` is constrained to `ValidatableRequest`, so a use case whose request
/// has no invariants cannot be wrapped here — wrapping it would be a silent no-op.
final class ValidationAsyncUseCaseDecorator<Request: ValidatableRequest, Response>: AsyncUseCase, Sendable {
    private let decoratee: any AsyncUseCase<Request, Response>

    init(decoratee: any AsyncUseCase<Request, Response>) {
        self.decoratee = decoratee
    }

    func execute(_ request: Request) async throws -> Response {
        try request.validate()
        return try await decoratee.execute(request)
    }
}
