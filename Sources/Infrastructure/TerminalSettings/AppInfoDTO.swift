import Foundation

/// Transport identity of an installed application resolved from a `.app` URL.
struct AppInfoDTO: Sendable {
    let bundleIdentifier: String
    let name: String
}
