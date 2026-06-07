import Foundation

struct CommandEntry: Equatable, Sendable {
    var line: String                 // single command line passed to /bin/sh -c
    /// The raw working-directory string as the user entered it: a fixed path, `nil`
    /// (run in the default directory), or the `<WORKING_DIRECTORY>` sentinel meaning
    /// "the global current directory" — kept as a String (not a `URL`) so the sentinel
    /// survives persistence; resolution to an actual directory happens at execution.
    var workingDirectory: String?
    var sink: CommandSink

    init(line: String, workingDirectory: String?, sink: CommandSink) {
        self.line = line
        self.workingDirectory = workingDirectory
        self.sink = sink
    }
}
