import Foundation
import Observation

@Observable
@MainActor
final class RunHistoryViewModel {
    static let displayLimit = 200

    private(set) var runs: [RunHistoryResponse] = []

    /// User-facing message for the most recent failed read/delete, surfaced as an
    /// alert. Operations set this instead of swallowing the error with `try?`, so a
    /// failed read (which would otherwise look like empty history) or a failed
    /// delete is visible rather than silent.
    var actionError: String?

    let entryID: UUID?
    let title: String

    private let readHistory: ReadHistoryUseCaseProtocol
    private let deleteHistory: DeleteHistoryUseCaseProtocol

    init(
        entryID: UUID?,
        title: String,
        readHistory: ReadHistoryUseCaseProtocol,
        deleteHistory: DeleteHistoryUseCaseProtocol
    ) {
        self.entryID = entryID
        self.title = title
        self.readHistory = readHistory
        self.deleteHistory = deleteHistory
    }

    func load() async {
        do {
            runs = try await readHistory.execute(ReadHistoryRequest(entryID: entryID))
        } catch is CancellationError {
            // `.task`-driven: the history window dis/appearing cancels this load.
            // Cancellation is normal control flow, not a user-facing failure — do
            // not surface it as an alert.
            return
        } catch {
            // Preserve the existing runs: a read failure must not masquerade as
            // empty history.
            actionError = error.localizedDescription
        }
    }

    func delete(_ run: RunHistoryResponse) async {
        do {
            try await deleteHistory.execute(DeleteHistoryRequest(scope: .run(run.id)))
        } catch {
            actionError = error.localizedDescription
            return
        }
        await load()
    }

    /// Clears this view's scope: one entry's history, or everything when global.
    func clearAll() async {
        let scope: DeleteHistoryRequest.Scope = entryID.map { .entry($0) } ?? .all
        do {
            try await deleteHistory.execute(DeleteHistoryRequest(scope: scope))
        } catch {
            actionError = error.localizedDescription
            return
        }
        await load()
    }
}
