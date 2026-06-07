import Foundation

/// One-shot startup use case: rewrites the stored terminal preference to its canonical
/// form so `loadPreference()` — called on every terminal command run — does not re-warn
/// on every read. Resets an undecodable blob to the default, or canonicalizes a
/// present-but-unparseable `launchMode` (keeping the selection). A no-op when the stored
/// value is already canonical or absent.
final class NormalizeTerminalPreferenceUseCase: SyncUseCase, Sendable {
    private let settings: any TerminalSettingsServiceProtocol

    init(settings: any TerminalSettingsServiceProtocol) {
        self.settings = settings
    }

    func execute(_ request: NormalizeTerminalPreferenceRequest) throws {
        _ = try settings.normalizeStoredPreference()
    }
}
