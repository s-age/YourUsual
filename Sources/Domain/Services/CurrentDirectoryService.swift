import Foundation

/// Owns the global current-directory intent: report the persisted value and replace it.
/// A thin settings service over the file-backed repository — it stores/returns the raw path
/// and makes no filesystem decision. Resolving the raw path to an actual directory (home
/// fallback, `~` expansion) is `WorkingDirectoryResolver`'s job, orchestrated by the
/// UseCase, so this Service does not depend on another Service or the filesystem.
final class CurrentDirectoryService: CurrentDirectoryServiceProtocol, Sendable {
    private let repository: any CurrentDirectoryRepositoryProtocol

    init(repository: any CurrentDirectoryRepositoryProtocol) {
        self.repository = repository
    }

    func current() -> CurrentDirectoryPreference {
        repository.loadPreference()
    }

    // Throwing: the backing store is a file (encode/I-O can fail), unlike the old in-memory
    // holder. Normalization (trim, blank → nil) stays here; the store maps nil → home.
    func setPath(_ path: String?) throws {
        // Normalize "blank" to unset so an empty submission resolves to home, matching
        // WorkingDirectoryResolver's empty handling.
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        try repository.savePreference(CurrentDirectoryPreference(path: (trimmed?.isEmpty == true) ? nil : trimmed))
    }
}
