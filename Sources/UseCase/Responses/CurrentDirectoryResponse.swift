import Foundation

/// The resolved global current directory surfaced to Presentation. `path` is always a
/// valid absolute directory (the raw value resolved through `WorkingDirectoryResolver`,
/// falling back to home when unset/invalid). Presentation abbreviates it for display.
struct CurrentDirectoryResponse: Equatable, Sendable {
    let path: String
}
