import Foundation

/// Owns the command-output setting intent: report the current buffer size and
/// persist a change. The valid-range clamp lives in `CommandOutputPreference`, so
/// this Service simply constructs the entity (clamping) and saves it.
final class CommandOutputSettingsService: CommandOutputSettingsServiceProtocol, Sendable {
    private let repository: any CommandOutputSettingsRepositoryProtocol

    init(repository: any CommandOutputSettingsRepositoryProtocol) {
        self.repository = repository
    }

    func current() -> CommandOutputPreference {
        repository.loadPreference()
    }

    // Non-throwing, unlike `TerminalSettingsService.setPreference`: the buffer size is a
    // single `UserDefaults` integer (a property-list primitive that cannot fail), whereas
    // the terminal preference is JSON encoded to a file (which can). The asymmetry is
    // intentional and not a swallowed error — see `CommandOutputPreferenceStore`.
    func setBufferLines(_ lines: Int) -> CommandOutputPreference {
        let preference = CommandOutputPreference(bufferLines: lines)   // clamps
        repository.savePreference(preference)
        return preference
    }
}
