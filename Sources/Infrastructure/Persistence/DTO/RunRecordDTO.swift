import Foundation

struct RunRecordDTO: Sendable {
    let id: UUID
    let entryID: UUID
    let entryName: String
    let executedAt: Date
    let outcomeKind: String     // `RunOutcome`-kind discriminator; currently always "command" (see CommandRunModel)
    let commandLine: String?
    let exitCode: Int32?
    let stdout: String?
    let stderr: String?
}
