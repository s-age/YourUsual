import Foundation

/// Persists a slider's new position. Issued once on drag release (never per throttle tick —
/// a per-tick whole-blob `replaceAllEntries` is heavy and widens the read→commit lost-update
/// window). Reads the registry before the transaction, applies the gerund transform, then
/// commits the whole collection — the standard whole-blob entry-registry shape.
final class SetSliderValueUseCase: AsyncUseCase, Sendable {
    private let entries: any SavedEntryServiceProtocol
    private let db: any DBProtocol
    private let diagnostics: any DiagnosticsLoggingProtocol

    init(
        entries: any SavedEntryServiceProtocol,
        db: any DBProtocol,
        diagnostics: any DiagnosticsLoggingProtocol
    ) {
        self.entries = entries
        self.db = db
        self.diagnostics = diagnostics
    }

    func execute(_ request: SetSliderValueRequest) async throws {
        do {
            let current = try await entries.listAll()
            let updated = entries.editingSliderValue(current, id: request.entryID, value: request.value)
            try await db.transaction { tx in try tx.replaceAllEntries(updated) }
        } catch {
            // Persisting the slider position is best-effort and the Presentation caller
            // swallows it (no alert for a self-correcting position save). Log it here so the
            // failure is observable instead of silently lost — the next load would otherwise
            // revert the slider with no explanation. Rethrow so the caller's `try?` still holds.
            diagnostics.warning(
                "Persisting slider position for \(request.entryID) failed: \(error.localizedDescription)")
            throw error
        }
    }
}
