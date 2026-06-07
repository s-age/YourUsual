import Foundation

/// Bridges the Domain `DiagnosticsLoggingProtocol` port to the Infrastructure
/// `DiagnosticsSinkProtocol` sink (mirrors `RegistryDatabaseGateway` bridging
/// `DBProtocol` to the transaction mechanism). Lets the UseCase emit diagnostics
/// without importing Infrastructure or `os`.
final class DiagnosticsLogger: DiagnosticsLoggingProtocol, Sendable {
    private let sink: any DiagnosticsSinkProtocol

    init(sink: any DiagnosticsSinkProtocol) {
        self.sink = sink
    }

    func warning(_ message: String) {
        sink.warning(message)
    }
}
