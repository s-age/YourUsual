import Foundation

final class ReadCommandOutputSettingsUseCase: SyncUseCase, Sendable {
    private let settings: any CommandOutputSettingsServiceProtocol

    init(settings: any CommandOutputSettingsServiceProtocol) {
        self.settings = settings
    }

    func execute(_ request: ReadCommandOutputSettingsRequest) throws -> CommandOutputSettingsResponse {
        CommandOutputSettingsResponse(preference: settings.current())
    }
}
