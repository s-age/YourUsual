import Foundation

/// Input for running a registered run-and-stream entry (a background command or an
/// AppleScript entry) and streaming its output. Carries the full entry so the use case
/// can resolve the target and scope a background command's run history by entry id.
struct RunStreamingEntryRequest: UseCaseRequest {
    let entry: SavedEntryResponse
}
