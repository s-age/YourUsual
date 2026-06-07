import Foundation

/// One incremental piece of a streaming command run: a slice of stdout/stderr as
/// it is produced, or the terminal exit status. Transport type — no domain meaning.
enum CommandStreamChunkDTO: Sendable {
    case stdout(String)
    case stderr(String)
    case exit(Int32)
}
