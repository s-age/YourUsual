import Foundation

/// Bridges the global current-directory intent to its file-backed infrastructure store.
/// The conversion is trivial (the entity is a single optional path string); the store
/// persists the value to a state file and self-heals a missing one to home.
final class CurrentDirectoryRepository: CurrentDirectoryRepositoryProtocol, Sendable {
    private let store: any CurrentDirectoryStoreProtocol

    init(store: any CurrentDirectoryStoreProtocol) {
        self.store = store
    }

    func loadPreference() -> CurrentDirectoryPreference {
        CurrentDirectoryPreference(path: store.loadPath())   // store self-heals; never nil
    }

    func savePreference(_ preference: CurrentDirectoryPreference) throws {
        try store.savePath(preference.path)                  // nil/blank → home default (store decides)
    }
}
