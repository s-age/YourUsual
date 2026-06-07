import Foundation

struct ResolveWorkingDirectoryRequest: UseCaseRequest {
    /// The user-supplied path; nil or empty resolves to the home directory.
    let path: String?
}
