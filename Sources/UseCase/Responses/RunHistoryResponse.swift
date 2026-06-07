import Foundation

struct RunHistoryResponse: Identifiable, Equatable, Sendable {
    let id: UUID
    let entryID: UUID
    let entryName: String
    let executedAt: Date
    let succeeded: Bool
    let exitCode: Int32?
    let commandLine: String?
    let stdout: String
    let stderr: String
}
