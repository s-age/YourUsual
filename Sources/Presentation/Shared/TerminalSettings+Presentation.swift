import Foundation

extension TerminalLaunchModeResponse {
    /// Human-readable label for the launch-mode radio control.
    var displayLabel: String {
        switch self {
        case .newWindow: return "Always new window"
        case .newTab:    return "Always new tab"
        case .reuse:     return "New tab first, then reuse"
        }
    }
}
