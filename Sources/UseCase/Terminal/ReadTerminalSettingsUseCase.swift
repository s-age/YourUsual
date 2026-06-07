import Foundation

final class ReadTerminalSettingsUseCase: SyncUseCase, Sendable {
    private let settings: any TerminalSettingsServiceProtocol

    init(settings: any TerminalSettingsServiceProtocol) {
        self.settings = settings
    }

    func execute(_ request: ReadTerminalSettingsRequest) throws -> TerminalSettingsResponse {
        TerminalSettingsResponse(
            preference: settings.current(),
            available: settings.availableTerminals()
        )
    }
}
