import Foundation

/// New top-to-bottom order for the entries of a single category. An empty or
/// single-element list is a no-op; validation is unnecessary.
struct ReorderEntriesRequest: UseCaseRequest {
    let orderedIDs: [UUID]
}
