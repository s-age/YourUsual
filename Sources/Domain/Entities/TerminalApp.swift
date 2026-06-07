import Foundation

enum TerminalApp: String, CaseIterable, Equatable, Sendable {
    case terminal  // Terminal.app
    case iterm     // iTerm2

    var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm:    return "com.googlecode.iterm2"
        }
    }
}
