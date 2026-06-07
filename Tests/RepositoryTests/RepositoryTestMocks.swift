import Foundation
@testable import YourUsual

/// No-op (capturing) diagnostics logger for Repository tests. Records messages so a
/// test can assert that a recovery/skip path emitted a warning.
final class MockDiagnosticsLogger: DiagnosticsSinkProtocol, @unchecked Sendable {
    private(set) var warnings: [String] = []

    func warning(_ message: String) {
        warnings.append(message)
    }
}
