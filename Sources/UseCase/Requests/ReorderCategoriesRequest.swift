import Foundation

/// New top-to-bottom order for the category sidebar. An empty or single-element
/// list is a no-op; validation is unnecessary.
struct ReorderCategoriesRequest: UseCaseRequest {
    let orderedIDs: [UUID]
}
