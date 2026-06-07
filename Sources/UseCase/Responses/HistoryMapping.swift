import Foundation

extension RunHistoryResponse {
    init(from record: RunRecord) {
        switch record.outcome {
        case .command(let c):
            self.init(
                id: record.id,
                entryID: record.entryID,
                entryName: record.entryName,
                executedAt: record.executedAt,
                succeeded: c.succeeded,
                exitCode: c.exitCode,
                commandLine: c.commandLine,
                stdout: c.stdout,
                stderr: c.stderr
            )
        }
    }
}
