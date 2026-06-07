import Foundation

/// One-shot legacy `registry.json` import decision, kept out of `SavedEntryService` so the
/// legacy reader does not linger as an implicit dependency of every entry use case. Holds
/// the entry repository only for the empty-store read that gates the import.
final class LegacyMigrationService: LegacyMigrationServiceProtocol, Sendable {
    private let repository: any SavedEntryRepositoryProtocol
    private let legacyRepository: any LegacyRegistryRepositoryProtocol

    init(
        repository: any SavedEntryRepositoryProtocol,
        legacyRepository: any LegacyRegistryRepositoryProtocol
    ) {
        self.repository = repository
        self.legacyRepository = legacyRepository
    }

    func importingLegacy() async throws -> [SavedEntry]? {
        // Read-modify decision runs here, before the UseCase opens the transaction.
        let current = try await repository.listAll()
        guard current.isEmpty else { return nil }            // store already populated → no-op
        guard let legacy = try await legacyRepository.listLegacy(),
              !legacy.isEmpty else { return nil }            // no legacy file / nothing to import
        return legacy
    }
}
