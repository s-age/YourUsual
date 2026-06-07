import Foundation

enum CommandSink: Equatable, Sendable {
    case background   // run in the background (result delivered as a notification)
    case terminal     // run in a terminal — which app + how comes from the global setting
}
