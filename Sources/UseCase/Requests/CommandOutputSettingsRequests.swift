import Foundation

struct ReadCommandOutputSettingsRequest: UseCaseRequest {}

/// Sets the command-output buffer size. The value is clamped into the valid range by
/// `CommandOutputPreference`, so no separate `validate()` is needed.
struct SetCommandOutputBufferRequest: UseCaseRequest {
    let bufferLines: Int
}
