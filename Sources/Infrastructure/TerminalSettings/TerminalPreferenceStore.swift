import Foundation

/// Persists the global terminal preference as JSON under a single `UserDefaults`
/// key. Stateless (reads `.standard` per call), so it is trivially `Sendable`.
final class TerminalPreferenceStore: TerminalPreferenceStoreProtocol, Sendable {
    private static let key = "terminalPreference"

    func load() throws -> TerminalPreferenceDTO? {
        guard let data = UserDefaults.standard.data(forKey: Self.key) else { return nil }
        // A decode failure means a corrupt blob — throw so the Repository can tell it
        // apart from "absent" (nil) and reset/log it through the injected diagnostics
        // logger. We no longer swallow to nil here (that hid corruption as a fresh
        // install and made it unresettable).
        return try JSONDecoder().decode(TerminalPreferenceDTO.self, from: data)
    }

    func save(_ dto: TerminalPreferenceDTO) throws {
        let data = try JSONEncoder().encode(dto)
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
