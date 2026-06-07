import Foundation

enum ValidationError: LocalizedError, Equatable, Sendable {
    case emptyField(name: String)              // a required input field was blank/whitespace
    case outOfRange(field: String, range: String)   // a numeric field fell outside its allowed range
    case invalidFormat(field: String, reason: String)   // a field broke a format rule (e.g. a missing token)

    var errorDescription: String? {
        switch self {
        case .emptyField(let name):
            return "\(name) is empty"
        case .outOfRange(let field, let range):
            return "\(field) must be in the range \(range)"
        case .invalidFormat(let field, let reason):
            return "\(field) \(reason)"
        }
    }
}
