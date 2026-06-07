import Foundation

/// Shared transport-recovery for a `RegisteredItemDTO`: decode via the single-source
/// `RegisteredItemMapper`, and on failure recover to an empty File/Directory entry
/// while **logging** the failure so the corruption is observable (never a bare `try?`).
///
/// Both the live read path (`SavedEntryRepository`) and the legacy import
/// (`LegacyRegistryRepository`) route through here so the recover+log boilerplate lives
/// once and cannot drift. `noun` names the source in the log line ("registry entry" vs
/// "legacy registry entry") — the only thing that differs between the two callers.
enum RegistryEntryRecovery {
    static func decodeOrRecover(
        _ dto: RegisteredItemDTO,
        noun: String,
        logger: any DiagnosticsSinkProtocol
    ) -> SavedEntry {
        do {
            return try RegisteredItemMapper.toEntity(dto)
        } catch {
            logger.warning(
                "\(noun) \(dto.id) failed to decode (\(error.localizedDescription)); "
                + "recovered as an empty File/Directory entry"
            )
            return RegisteredItemMapper.recoveredEntity(from: dto)
        }
    }
}
