import Foundation

/// Runs a slider's command for a given value — issued repeatedly while dragging (throttled
/// by Presentation) and once on release. Carries the resolved entry so the use case can read
/// the slider's command template without a second store read.
struct RunSliderRequest: UseCaseRequest {
    let entry: SavedEntryResponse
    let value: Double
}

/// Persists a slider's new position. Issued once on drag release (never per throttle tick).
struct SetSliderValueRequest: UseCaseRequest {
    let entryID: UUID
    let value: Double
}
