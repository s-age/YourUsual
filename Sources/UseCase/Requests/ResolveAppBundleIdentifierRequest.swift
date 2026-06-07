import Foundation

struct ResolveAppBundleIdentifierRequest: UseCaseRequest {
    /// File URL of the `.app` the user picked to open a path with.
    let url: URL
}
