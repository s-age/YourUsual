import Foundation

/// Errors for **operations that fail at runtime** — locating an item, opening a target,
/// running a command, launching a terminal, persisting the registry. One of the app's
/// two failure-domain enums in the shared `Error` leaf layer; the other is
/// `ValidationError` (request validation). Named after its failure domain per
/// `arch-error.md` ("one enum per failure domain").
///
/// Lives in `Error` (depends only on `Foundation`), so it is referenceable from every
/// layer — being thrown/caught in `Infrastructure` is by design, not an upward-import
/// violation.
enum OperationError: LocalizedError, Equatable, Sendable {
    case invalidItem(reason: String)      // target/handler incompatible, empty fields
    case itemNotFound(id: UUID)
    case categoryNotFound(id: UUID)       // move target category no longer exists
    case targetNotFound(path: String)     // file/dir no longer exists
    case targetOpenFailed(path: String)   // exists, but the OS refused to open it
    case appNotFound(bundleIdentifier: String)
    case commandFailed(exitCode: Int32, stderr: String)
    case terminalLaunchFailed(reason: String)
    case applescriptFailed(reason: String)
    case persistenceFailed(reason: String)
    case misroutedEntry(reason: String)   // a kind reached a use case its routing should never send it to

    var errorDescription: String? {
        switch self {
        case .invalidItem(let reason):        return "Invalid item: \(reason)"
        case .itemNotFound(let id):           return "Item not found: \(id)"
        case .categoryNotFound(let id):       return "Category not found: \(id)"
        case .targetNotFound(let path):       return "Path not found: \(path)"
        case .targetOpenFailed(let path):     return "Could not open: \(path)"
        case .appNotFound(let id):            return "App not found: \(id)"
        case .commandFailed(let code, _):     return "Command failed (exit \(code))"
        case .terminalLaunchFailed(let r):    return "Terminal launch failed: \(r)"
        case .applescriptFailed(let r):       return "AppleScript failed: \(r)"
        case .persistenceFailed(let r):       return "Could not save registry: \(r)"
        case .misroutedEntry(let r):          return "Routing error: \(r)"
        }
    }
}
