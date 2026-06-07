import Foundation

enum EntryKind: Equatable, Sendable {
    case browse(BrowseEntry)
    case command(CommandEntry)
    case appleScript(AppleScriptEntry)
    case slider(SliderEntry)
}
