import Foundation

/// Reference implementation of the UseCase-owned transaction.
/// The boundary lives here: the deletion is applied inside `db.transaction`,
/// which commits on success and rolls back if the body throws. The body is
/// synchronous (SwiftData's transaction cannot span `await`) and only *applies*
/// the already-decided mutation via the `tx` capability token — there is no
/// other write path **into the SwiftData registry**. (Preference blobs persist on
/// a separate substrate outside `transaction`; see `arch.md` → "Transaction
/// control" carve-out.)
final class DeleteHistoryUseCase: AsyncUseCase, Sendable {
    private let db: any DBProtocol

    init(db: any DBProtocol) {
        self.db = db
    }

    func execute(_ request: DeleteHistoryRequest) async throws {
        let scope = request.scope
        try await db.transaction { tx in
            switch scope {
            case .run(let id):   try tx.deleteRun(id: id)
            case .entry(let id): try tx.deleteAllRuns(forEntry: id)
            case .all:           try tx.deleteAllRuns()
            }
        }
    }
}
