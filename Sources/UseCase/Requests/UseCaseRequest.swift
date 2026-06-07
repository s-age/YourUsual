import Foundation

/// Marker for every UseCase input DTO consumed by Presentation and the use cases.
/// A bare `UseCaseRequest` carries no invariants (reads, empty requests, no-op
/// reorders) — it is just the shared input type. Requests that *do* have input
/// constraints conform to `ValidatableRequest` instead.
protocol UseCaseRequest: Sendable {}

/// A `UseCaseRequest` that carries input invariants. There is **no** default
/// `validate()`, so a conformer must implement a real check — and the
/// `Validation*UseCaseDecorator` is constrained to this protocol, so:
///
/// - wrapping a non-validating request is a compile error (it can't be a silent
///   no-op wrap), and
/// - conforming to `ValidatableRequest` is the explicit, greppable signal that a
///   request *needs* a decorator in `UseCaseContainer`.
///
/// Concrete use cases never call `validate()` themselves — only the decorator does.
protocol ValidatableRequest: UseCaseRequest {
    func validate() throws
}
