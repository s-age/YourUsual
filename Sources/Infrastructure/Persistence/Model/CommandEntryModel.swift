import Foundation
import SwiftData

/// Per-type table for command entries — holds only the fields a command entry needs.
@Model
final class CommandEntryModel {
    var commandLine: String           // required — shell command line
    var workingDirectory: String?     // legitimately optional
    var sink: String                  // "background" | "terminal"

    var entry: EntryModel?            // inverse of EntryModel.command (cascade parent)

    init(commandLine: String, workingDirectory: String?, sink: String) {
        self.commandLine = commandLine
        self.workingDirectory = workingDirectory
        self.sink = sink
    }
}
