import Foundation

struct ReadCurrentDirectoryRequest: UseCaseRequest {}

/// Replaces the global current directory. An empty/blank path clears it back to "unset"
/// (which resolves to home), so there is no non-empty invariant — this is a bare
/// `UseCaseRequest`, not a `ValidatableRequest`.
struct SetCurrentDirectoryRequest: UseCaseRequest {
    let path: String?
}
