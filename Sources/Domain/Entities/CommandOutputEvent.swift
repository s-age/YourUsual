import Foundation

/// One step in a streaming command run: a slice of output as it is produced, or
/// the terminal exit status. Domain-level view of `CommandStreamChunkDTO`.
enum CommandOutputEvent: Equatable, Sendable {
    case stdout(String)
    case stderr(String)
    case exit(Int32)
}
