import Foundation

/// Reads the legacy `registry.json` (via the Infrastructure reader) and converts it
/// to domain entities through `RegisteredItemMapper` — the same decoder the live read
/// path (`SavedEntryRepository`) uses, so the legacy `executable`+`arguments` fallback
/// and undecodable-record recovery come for free. Returns nil when no legacy file
/// exists. The *decision* to import (only into an empty store) belongs to the Domain
/// Service; this layer only supplies the decoded entities.
final class LegacyRegistryRepository: LegacyRegistryRepositoryProtocol, Sendable {
    private let reader: any LegacyRegistryReaderProtocol
    private let logger: any DiagnosticsSinkProtocol

    init(reader: any LegacyRegistryReaderProtocol, logger: any DiagnosticsSinkProtocol) {
        self.reader = reader
        self.logger = logger
    }

    func listLegacy() async throws -> [SavedEntry]? {
        guard let dto = try await reader.readLegacy() else { return nil }
        // Transport recovery (shared with the live read path): an undecodable record
        // must not fail the whole import — recover + log via RegistryEntryRecovery.
        return dto.items.map {
            RegistryEntryRecovery.decodeOrRecover($0, noun: "legacy registry entry", logger: logger)
        }
    }
}
