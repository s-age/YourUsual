import Foundation

/// Moves one entry into another category. A no-op when the entry already
/// belongs to the target; validation is unnecessary.
struct MoveEntryToCategoryRequest: UseCaseRequest {
    let entryID: UUID
    let categoryID: UUID
}
