import Foundation

final class SetCommandOutputBufferUseCase: SyncUseCase, Sendable {
    private let settings: any CommandOutputSettingsServiceProtocol

    init(settings: any CommandOutputSettingsServiceProtocol) {
        self.settings = settings
    }

    /// Persists the buffer size and reports the resulting state — the value may be
    /// clamped to the valid range (see `CommandOutputPreference`).
    func execute(_ request: SetCommandOutputBufferRequest) throws -> CommandOutputSettingsResponse {
        CommandOutputSettingsResponse(preference: settings.setBufferLines(request.bufferLines))
    }
}
