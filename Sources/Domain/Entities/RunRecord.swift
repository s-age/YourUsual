import Foundation

struct RunRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let entryID: UUID         // owning entry — cascade parent
    let entryName: String     // snapshot at run time
    let executedAt: Date
    let outcome: RunOutcome

    init(
        id: UUID = UUID(),
        entryID: UUID,
        entryName: String,
        executedAt: Date,
        outcome: RunOutcome
    ) {
        self.id = id
        self.entryID = entryID
        self.entryName = entryName
        self.executedAt = executedAt
        self.outcome = outcome
    }

    var succeeded: Bool {
        switch outcome {
        case .command(let c): return c.succeeded
        }
    }

    /// Builds a command run record, owning the `RunOutcome.command` variant selection
    /// so call sites (the streaming run UseCase) never pick the outcome case by hand.
    /// `executedAt` is passed in (the UseCase injects a clock) rather than read here.
    static func command(
        id: UUID = UUID(),
        entryID: UUID,
        entryName: String,
        executedAt: Date,
        outcome: CommandRunOutcome
    ) -> RunRecord {
        RunRecord(
            id: id,
            entryID: entryID,
            entryName: entryName,
            executedAt: executedAt,
            outcome: .command(outcome)
        )
    }
}
