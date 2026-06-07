import Foundation

/// Bridges the command-output setting to infrastructure: loads/persists the buffer
/// size via `CommandOutputPreferenceStore`. Primitive ↔ entity conversion only — no
/// decision-making (the valid-range clamp is the entity's).
final class CommandOutputSettingsRepository: CommandOutputSettingsRepositoryProtocol, Sendable {
    private let store: any CommandOutputPreferenceStoreProtocol

    init(store: any CommandOutputPreferenceStoreProtocol) {
        self.store = store
    }

    func loadPreference() -> CommandOutputPreference {
        guard let lines = store.loadBufferLines() else { return .default }
        return CommandOutputPreference(bufferLines: lines)   // clamps a stale/out-of-range value
    }

    func savePreference(_ preference: CommandOutputPreference) {
        store.saveBufferLines(preference.bufferLines)
    }
}
