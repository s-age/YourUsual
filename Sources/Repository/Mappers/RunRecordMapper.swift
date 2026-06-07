import Foundation

/// Single source of truth for `RunRecordDTO` ⇄ `RunRecord` conversion, **including
/// the persisted outcome discriminator**. Both the write path
/// (`RegistryDatabaseGateway`) and the read path (`RunHistoryRepository`) route
/// through here so the encode/decode pair cannot drift apart.
enum RunRecordMapper {
    /// `RunRecordDTO.outcomeKind` values.
    private enum OutcomeKind {
        static let command = "command"
    }

    // MARK: - Entity → DTO

    static func toDTO(_ run: RunRecord) -> RunRecordDTO {
        switch run.outcome {
        case .command(let c):
            return RunRecordDTO(
                id: run.id,
                entryID: run.entryID,
                entryName: run.entryName,
                executedAt: run.executedAt,
                outcomeKind: OutcomeKind.command,
                commandLine: c.commandLine,
                exitCode: c.exitCode,
                stdout: c.stdout,
                stderr: c.stderr
            )
        }
    }

    // MARK: - DTO → Entity

    /// Decodes a stored run record. Throws `OperationError.persistenceFailed` when the
    /// outcome discriminator is unknown; the caller decides whether to skip it.
    static func toEntity(_ dto: RunRecordDTO) throws -> RunRecord {
        RunRecord(
            id: dto.id,
            entryID: dto.entryID,
            entryName: dto.entryName,
            executedAt: dto.executedAt,
            outcome: try decodeOutcome(dto)
        )
    }

    private static func decodeOutcome(_ dto: RunRecordDTO) throws -> RunOutcome {
        switch dto.outcomeKind {
        case OutcomeKind.command:
            return .command(CommandRunOutcome(
                commandLine: dto.commandLine ?? "",
                result: CommandResult(
                    exitCode: dto.exitCode ?? -1,
                    stdout: dto.stdout ?? "",
                    stderr: dto.stderr ?? ""
                )
            ))
        default:
            throw OperationError.persistenceFailed(reason: "unknown run outcomeKind: \(dto.outcomeKind)")
        }
    }
}
