import Foundation
import os

/// Reads the legacy `registry.json` file (the pre-SwiftData persistence format) and
/// decodes it into the transport `RegistryDTO`. This is pure transport I/O: it does
/// **not** decide *whether* to import (that is a Domain decision, gated on an empty
/// store) and it does **not** open a transaction (the UseCase owns that boundary —
/// see `MigrateLegacyRegistryUseCase`).
///
/// Returns nil when no legacy file is present (the normal fresh-install path). When a
/// file IS present but cannot be read or decoded it throws, so the boot layer can
/// surface the failure instead of dropping the user's old data invisibly. Legacy
/// `executable`+`arguments` reconstruction is **not** done here — it is handled on the
/// DTO→entity path by `RegisteredItemMapper`, the same decoder the live read uses.
final class LegacyRegistryReader: LegacyRegistryReaderProtocol, Sendable {
    private static let log = Logger(subsystem: "com.yourusual.app", category: "LegacyRegistryReader")
    private let legacyURL: URL

    init(legacyURL: URL = LegacyRegistryReader.defaultLegacyURL) {
        self.legacyURL = legacyURL
    }

    func readLegacy() async throws -> RegistryDTO? {
        let url = legacyURL
        // A missing legacy file is the normal, expected path (fresh install) — not an
        // error. Only a present-but-unreadable file is worth logging/throwing.
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let rawData = await Task.detached(priority: .utility) {
            try? Data(contentsOf: url)
        }.value
        guard let rawData else {
            // The file is present but unreadable — the user HAS old data we are failing
            // to import. Log AND throw so the boot layer can tell them, instead of
            // dropping the registry invisibly. The file is left on disk for a retry.
            Self.log.error("Legacy registry exists at \(url.path, privacy: .public) but could not be read")
            throw OperationError.persistenceFailed(
                reason: "Your previous settings file at \(url.path) could not be read.")
        }
        do {
            return try JSONDecoder().decode(RegistryDTO.self, from: rawData)
        } catch {
            let path = url.path
            let reason = error.localizedDescription
            Self.log.error("Legacy registry at \(path, privacy: .public) failed to decode: \(reason, privacy: .public)")
            throw OperationError.persistenceFailed(
                reason: "Your previous settings file at \(path) is corrupt and could not be imported (\(reason)).")
        }
    }

    static var defaultLegacyURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "com.yourusual.app", directoryHint: .isDirectory)
            .appending(path: "registry.json", directoryHint: .notDirectory)
    }
}
