import Foundation

/// Snapshot of the global command-output setting for the settings pane: the current
/// buffer size plus the valid range the field should accept.
struct CommandOutputSettingsResponse: Sendable, Equatable {
    let bufferLines: Int
    let minBufferLines: Int
    let maxBufferLines: Int
}

// MARK: - Entity → Response

extension CommandOutputSettingsResponse {
    init(preference: CommandOutputPreference) {
        self.init(
            bufferLines: preference.bufferLines,
            minBufferLines: CommandOutputPreference.minBufferLines,
            maxBufferLines: CommandOutputPreference.maxBufferLines
        )
    }
}
