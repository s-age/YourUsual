import Foundation

enum RunOutcome: Equatable, Sendable {
    case command(CommandRunOutcome)
    // future: case browse(BrowseRunOutcome), case terminalLaunch(...)
}
