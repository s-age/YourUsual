import Foundation

final class RunHistoryService: RunHistoryServiceProtocol, Sendable {
    private let repository: any RunHistoryRepositoryProtocol
    /// Injected clock for a record's `executedAt`. Stamping the run time is a
    /// history-domain concern, so it lives here rather than in the UseCase — and
    /// stays deterministic in tests.
    private let now: @Sendable () -> Date

    init(
        repository: any RunHistoryRepositoryProtocol,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.now = now
    }

    func list(forEntry id: UUID) async throws -> [RunRecord] {
        try await repository.list(forEntry: id)
    }

    func listAll() async throws -> [RunRecord] {
        try await repository.listAll()
    }

    func makeRunRecord(
        forEntry entryID: UUID, named entryName: String,
        command: CommandEntry, result: CommandResult
    ) -> RunRecord {
        RunRecord.command(
            entryID: entryID,
            entryName: entryName,
            executedAt: now(),
            outcome: CommandRunOutcome(commandLine: command.line, result: result)
        )
    }
}
