import Foundation

final class SetTerminalPreferenceUseCase: SyncUseCase, Sendable {
    private let settings: any TerminalSettingsServiceProtocol

    init(settings: any TerminalSettingsServiceProtocol) {
        self.settings = settings
    }

    /// Persists the selection, then reports the resulting state — the mode may be
    /// clamped to one the chosen app supports (see `TerminalPreference`).
    func execute(_ request: SetTerminalPreferenceRequest) throws -> TerminalSettingsResponse {
        let preference = try settings.setPreference(
            selection: request.selection,
            launchMode: request.launchMode.toDomain
        )
        return TerminalSettingsResponse(
            preference: preference,
            available: settings.availableTerminals()
        )
    }
}
