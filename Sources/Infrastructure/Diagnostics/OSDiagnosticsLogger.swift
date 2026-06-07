import Foundation
import os

/// Writes diagnostics to the unified logging system (`os.Logger`). This is the only
/// place `os` is touched on behalf of the Repository layer's data-recovery paths
/// (decode failures recovered or skipped), keeping `os` out of `Repository`.
final class OSDiagnosticsLogger: DiagnosticsSinkProtocol, Sendable {
    private let log: Logger

    init(category: String) {
        log = Logger(subsystem: "com.yourusual.app", category: category)
    }

    func warning(_ message: String) {
        // Recovery diagnostics carry only ids + decode reasons (no user file paths),
        // so they are safe to record publicly for local debugging.
        log.warning("\(message, privacy: .public)")
    }
}
