import Foundation

enum AppChoice: Equatable, Sendable {
    case `default`                          // open with the system default app
    case app(bundleIdentifier: String)      // open with a specific app
}
