import Foundation

struct CommandResult: Equatable, Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    var succeeded: Bool { exitCode == 0 }

    init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}
