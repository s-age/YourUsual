import Foundation

/// Cross-cutting diagnostics port the UseCase layer may emit through for
/// best-effort, non-critical failures that are otherwise swallowed (e.g. a
/// background run completes but persisting its history fails). Records the
/// failure so it is *observable* in the unified log instead of silently lost.
///
/// Placed in `Domain/Entities` for the same reason as `DBProtocol`: a capability
/// protocol shared across layers lives here so both UseCase and Repository may
/// reference it without an upward import. The concrete `os.Logger` sink is
/// Infrastructure (`OSDiagnosticsLogger`); a Repository adapter (`DiagnosticsLogger`)
/// bridges this port to it, keeping `os` out of UseCase.
protocol DiagnosticsLoggingProtocol: Sendable {
    func warning(_ message: String)
}
